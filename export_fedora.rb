#!/usr/bin/ruby

## Fedora Commons (Version 3) Export Tool for Islandora migration & Cold Storage. 
## Author: Paul
## Contact Details: https://github.com/newzealandpaul/

require 'bundler/setup'
require 'rubydora'
require 'fileutils'
require 'yaml'
require 'sqlite3'
require 'json'
require 'optparse'

def load_config
  begin
    script_dir = File.expand_path(File.dirname(__FILE__))
    config_path = File.join(script_dir, 'config.yml')
    secrets_path = File.join(script_dir, 'SECRETS.yml')

    config = File.exist?(config_path) ? YAML.safe_load_file(config_path) : {}
    secrets = File.exist?(secrets_path) ? YAML.safe_load_file(secrets_path) : {}
    keys = config.merge(secrets)

    return keys
  rescue => e
    puts "Error loading keys: #{e.message}"
    return false
  end
end
  
# Connect to Fedora
def connect(repo_url, repo_user, repo_password)
  begin
    repo = Rubydora.connect :url => repo_url, :user => repo_user, :password => repo_password
    # Test the connection
    if repo.find("qsr-object:189208").datastreams.key? "RDF"
      return repo
    else
      raise "Datastream 'RDF' not found"
    end
  rescue => e
    puts "Error connecting to Fedora: #{e.message}"
    return false
  end
end

def export_fedora_object(pid)
    o = $repo.find(pid)
    return o.datastreams["RDF"].content.body
end

def create_object_directory(object, base_dir)
  begin
    # Split the object into type and id
    type, id = object.split(':')
    raise "Invalid object format" if type.nil? || id.nil? || id.length < 2

    # Create the directory structure
    type_dir = File.join(base_dir, type)
    id_prefix_dir = File.join(type_dir, id[0..1])
    full_id_dir = File.join(id_prefix_dir, id)
    datastreams_dir = File.join(full_id_dir, "datastreams")

    # Create directories if they don't exist
    FileUtils.mkdir_p(datastreams_dir)

    # Return the full path to the object directory
    return full_id_dir
  rescue => e
    # Print the error message and return false
    puts "Error: #{e.message}"
    return false
  end
end

def test(id)

  puts "Testing with Object: " + id
  
  object = $repo.find(id)
  object.datastreams.key? "RDF"
  puts "Datastreams: " + object.datastreams.keys.join(", ")
  puts "RDF Content Type: " + object.datastreams["RDF"].content.headers[:content_type]
  puts "RDF Content: " + object.datastreams["RDF"].content.body
  dir = create_object_directory("qsr-object:189208", "export")
  if dir == false
    puts "Error creating object directory"
    throw "Error creating object directory"
  end
  File.exists?(dir) ? (puts "Object Dir Exists") : (puts "Object Dir Does Not Exist")
  puts "Object Dir: " + dir
  write_all_object_datastreams(id)
  return object
end

def write_all_object_datastreams(id)
  object = $repo.find(id)
  dir = create_object_directory(id, $export_base_dir)
  datastream_metadata = {}

  object.datastreams.each do |dsid, ds|
    mine_type = ds.content.headers[:content_type]
    if mine_type.include? "xml"
      ext = ".xml"
    elsif $mime_types.key? mine_type
      ext = "." + $mime_types[mine_type]
    else
      ext = ".bin"
    end
    path = File.join(dir, "datastreams" , dsid + ext)
    File.open(path, 'w') { |f| f.write(ds.content.body) }
    
    metadata = ds.profile.to_hash
    metadata_path = File.join(dir, "datastreams", dsid + "_metadata.json")
    File.open(metadata_path, 'w') { |f| f.write(JSON.pretty_generate(metadata)) }
    
    creation_date = metadata["dsCreateDate"]
    puts "Wrote datastream: #{dsid} to #{path} with creation date: #{creation_date}"
    
    if creation_date
      begin
        # Convert creation_date to Time object if it's a string
        creation_time = case creation_date
          when String then Time.parse(creation_date)
          when Time then creation_date
          else nil
        end
        
        File.utime(creation_time, creation_time, path) if creation_time
      rescue StandardError => e
        puts "Warning: Could not set timestamp for #{path}: #{e.message}"
      end
    end
    datastream_metadata[dsid] = {
      "mime_type" => mine_type,
      "datastream_file" => "datastreams/" + dsid + ext,
      "metadata_file" => metadata_path,
      "metadata" => metadata
    }
  end
  metadata = object.profile.to_hash
  metadata["datastreams"] = datastream_metadata
  metadata_path = File.join(dir, id.gsub(":","-") + "_metadata.json")
  File.open(metadata_path, 'w') { |f| f.write(JSON.pretty_generate(metadata)) }

end

def load_mime_types(file_path)
  # Apache mimetype file: https://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types
  mime_types = {}
  
  File.foreach(file_path) do |line|
    next if line.start_with?('#') || line.strip.empty?    
    parts = line.strip.split(/\s+/)
  
    if parts.size >= 2
      mime_type = parts[0]
      first_extension = parts[1]
      
      # Add to hash only if we haven't seen this mime type before
      mime_types[mime_type] ||= first_extension
    end
  end
  
  return mime_types
end

def initialize_db(db_path, id_listing_path=nil)
  begin
    unless File.exist?(db_path)
      db = SQLite3::Database.new(db_path)
      db.execute <<-SQL
        CREATE TABLE objects (
          id TEXT UNIQUE NOT NULL,
          status TEXT,
          processing_start DATETIME,
          processing_end DATETIME,
          directory_path TEXT,
          metadata JSON,
          error TEXT
        );
      SQL
      puts "Database created and table 'objects' initialized."
      if id_listing_path && File.exist?(id_listing_path)
        load_ids_from_file(db, id_listing_path)
      end
      return SQLite3::Database.new(db_path)
    else
      puts "Database already exists."
      return SQLite3::Database.new(db_path)
    end
  rescue => e
    puts "Error initializing database: #{e.message}"
    return false
  end
end

def load_ids_from_file(db, id_listing_path)
  begin
    File.open(id_listing_path, 'r') do |f|
      count = 1
      f.each_line do |line|
        id = line.strip
        db.execute("INSERT INTO objects (id, status) VALUES (?, ?)", [id, "pending"])
        if count % 1000 == 0
          puts "#{count} IDs loaded from file."
        end
        count += 1
      end
    end
    count = db.execute("SELECT COUNT(*) FROM objects")[0][0]
    puts "#{count} IDs loaded from file."
  rescue => e
    puts "Error loading IDs from file: #{e.message}"
    puts e.backtrace
  end
end

def process_single(id, dry_run: false)
  begin
    if $db.nil?
      raise "Database not initialized"
    end
    if id.nil?
      raise "No ID specified"
    end
    puts "Processing object: #{id}"
    $db.execute("UPDATE objects SET status = 'processing', processing_start = datetime('now') WHERE id = ?", [id])
    object = export_fedora_object(id)
    dir = create_object_directory(id, $export_base_dir)
    if dir == false
      raise "Error creating object directory"
    end
    write_all_object_datastreams(id)
    $db.execute("UPDATE objects SET status = 'complete', processing_end = datetime('now'), directory_path = ? WHERE id = ?", [dir, id])
  rescue => e
    puts "Error processing object: #{e.message}"
    puts e.backtrace
    $db.execute("UPDATE objects SET status = 'error', processing_end = datetime('now'), error = ? WHERE id = ?", [e.message, id])
  end
end

def full_run(dry_run: false, limit: nil)
  begin
    if $db.nil?
      raise "Database not initialized"
    end
    if limit
      puts "Processing up to #{limit} objects."
    else
      puts "Processing all objects."
    end
    ids = $db.execute("SELECT id FROM objects WHERE status = 'pending' LIMIT ?", limit)
    ids.each do |row|
      id = row[0]
      process_single(id, dry_run: dry_run)
    end
  rescue => e
    puts "Error during full run: #{e.message}"
    puts e.backtrace
  end
end

def setup_globals
  config = load_config()
  fedora_user = config['fedora_user']
  fedora_password = config['fedora_password']
  fedora_url = config['fedora_url']
  $export_base_dir = config['base_dir']
  $sqlite_db_path = config['sqlite_db']
  $id_listing_path = config['id_listing']
  $mime_types = load_mime_types(config['mime_types'])
  $repo = connect(fedora_url, fedora_user, fedora_password)
  $test_object = config['test_object']
  
  if $sqlite_db_path != nil && File.file?($sqlite_db_path)
    $db = initialize_db($sqlite_db_path, $id_listing_path)
  end
end

def parse_options
  options = {
    debug: false,
    mode: nil
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: export_fedora.rb [options]"

    opts.on("--debug", "Enable debug mode") do
      options[:debug] = true
    end

    opts.on("--test", "Process test object from config") do
      raise "Only one mode can be specified" if options[:mode]
      options[:mode] = :test
    end

    opts.on("--single ID", "Process single object by ID") do |id|
      raise "Only one mode can be specified" if options[:mode]
      options[:mode] = :single
      options[:id] = id
    end

    opts.on("--fullrun [LIMIT]", Integer, "Process all objects, optionally limit count") do |limit|
      raise "Only one mode can be specified" if options[:mode]
      options[:mode] = :fullrun
      options[:limit] = limit
    end

    opts.on("--dryrun [LIMIT]", Integer, "Simulate full run, optionally limit count") do |limit|
      raise "Only one mode can be specified" if options[:mode]
      options[:mode] = :dryrun
      options[:limit] = limit
    end
  end.parse!

  options
end

def main
  options = parse_options
  setup_globals()

  case options[:mode]
  when :test
    test($test_object)
  when :single
    process_single(options[:id])
  when :fullrun
    full_run(dry_run: false, limit: options[:limit])
  when :dryrun
    full_run(dry_run: true, limit: options[:limit])
  else
    puts "No valid mode specified. Use --help for usage information."
  end

  start_debug_session if options[:debug]
end

def start_debug_session
  require 'irb'
  require 'irb/completion'
  ARGV.clear
  IRB.setup nil
  IRB.conf[:PROMPT_MODE] = :SIMPLE
  IRB.conf[:LOAD_MODULES] = [] unless IRB.conf.key?(:LOAD_MODULES)
  irb = IRB::Irb.new
  IRB.conf[:MAIN_CONTEXT] = irb.context
  irb.eval_input
end

if __FILE__ == $0
  main
end