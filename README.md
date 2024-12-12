# Fedora Commons (Version 3) Export Tool for Islandora migration & Cold Storage. 

<span style="color: red">**⚠️ This is unsupported software. ⚠️**</span>

A Ruby script for exporting objects and their datastreams from a Fedora Commons repository (v3). This tool preserves object metadata and handles various MIME types appropriately. This is useful it you want to shift from a legacy [Islandora](https://www.islandora.ca/) installation to a newer Digital Asset Manager / CMS. 

It may need modifications to work in your specific legacy Islandora installation.

**Note:** To initialize the database, if you are planning on using the database queue feature, you need a text file with one object ID per line. This could be generated using Apache Solr if you have a Solr indexing Fedora. The text file should look something like this:

```
example-object:123001
example-object:123002
example-object:123010
example-object:124091
```

## Features

- Exports all datastreams for specified Fedora objects.
- Preserves creation dates and metadata.
- Handles various MIME types (XML, binary, etc.).
- SQLite database tracking for export progress.
- Configurable export paths and repository connections.

## Installation

1. Ensure Ruby, RubyGems and Ruby-devel/-dev is installed on your system 

```bash
# Example Install on RHEL 9
sudo dnf install ruby rubygems ruby-devel
# Example on Debian / Ubuntu 
sudo apt-get install ruby-full
```

2. Clone this repository
3. Install required gems:

```bash
bundle config set --local path 'vendor/bundle'
bundle install
```

## Configuration

Create two configuration files in the script directory:

1. config.yml - General configuration:

```yaml
export_base_dir: "/path/to/export/directory"
fedora_url: "http://your-fedora-server:8080/fedora"
sqlite_db: queue.sqlite3
id_listing: "../object_ids.txt"
mime_types: mime.types
test_object: example-object:123456
```

2. SECRETS.yml - Sensitive credentials:

```yaml
username: "fedora_username"
password: "fedora_password"
```

## Usage 

1. Prepare a text file with Fedora object IDs (one per line)
2. Change values in the config.yml and SECRETS.yml file.
2. Run the script.

```bash
# Examples of running the script
ruby export_fedora.rb --debug
ruby export_fedora.rb --test
ruby export_fedora.rb --single object:123
# Full run and dry run require you to specify how many objects to process
ruby export_fedora.rb --fullrun 10000
ruby export_fedora.rb --dryrun 10000
```

## Output Structure

```
export_directory/
  └── object_id
     └── 12
         └── 12001
              └── datastreams
                  ├── DS1.xml
                  ├── DS1_metadata.json
                  ├── DS2.bin
                  └── DS2_metadata.json
```

## License

Apache License, Version 2.0

## Credit

[mime.types](https://svn.apache.org/repos/asf/httpd/httpd/trunk/docs/conf/mime.types) is from the Apache HTTPD project (Apache License, Version 2.0). 

The now deprecated [rubydora](https://github.com/samvera-deprecated/rubydora) project. 

## Copyright

Copyright © 2024 University of Canterbury. All rights reserved.