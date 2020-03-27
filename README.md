# Bulkrax
Bulkrax is a batteries included importer for Samvera applications. It currently includes support for OAI-PMH (DC and Qualified DC) and CSV out of the box. It is also designed to be extensible, allowing you to easily add new importers in to your application or to include them with other gems. Bulkrax provides a full admin interface including creating, editing, scheduling and reviewing imports.


## Installation

### Install Generator

Add this line to your application's Gemfile:

```ruby
gem 'bulkrax', git: 'https://github.com/samvera-labs/bulkrax.git'
```

And then execute:
```bash
$ bundle update
$ rails generate bulkrax:install
```

If using Sidekiq, setup queues for `import` and `export`. 

### Manual Installation

Add this line to your application's Gemfile:

```ruby
gem 'bulkrax', git: 'https://github.com/samvera-labs/bulkrax.git'
```

And then execute:
```bash
$ bundle install
```

Mount the engine in your routes file

```ruby 
mount Bulkrax::Engine, at: '/'
```

If using Sidekiq, setup queues for `import` and `export`. 

```ruby 
# in config/sidekiq.yml
:queues:
  - default
  - import # added
  - export # added
  # your other queues ...
```

```ruby 
# in app/assets/javascripts/application.js - before //= require_tree .
//= require bulkrax/application
```

You'll want to add an intializer to configure the importer to your needs:

```ruby
# config/initializers/bulkrax.rb
Bulkrax.setup do |config|
  # some configuration
end
```

The [configuration guide](https://github.com/samvera-labs/bulkrax/wiki/Configuration) provides detailed instructions on the various available configurations.

Example:

```
Bulkrax.setup do | config |
  # If the work type isn't provided during import, use Image 
  config.default_work_type = 'Image'

  # Use identifier to store the unique import identifier
  config.system_identifier_field = 'identifier'

  # Setup a field mapping for the OaiDcParser
  # Your application metadata fields are the key
  #   from: fields in the incoming source data
  config.field_mappings = {
    "Bulkrax::OaiDcParser" => {
      "contributor" => { from: ["contributor"] },
      "creator" => { from: ["creator"] },
      "date_created" => { from: ["date"] },
      "description" => { from: ["description"] },
      "identifier" => { from: ["identifier"] },
      "language" => { from: ["language"], parsed: true },
      "publisher" => { from: ["publisher"] },
      "related_url" => { from: ["relation"] },
      "rights_statement" => { from: ["rights"] },
      "source" => { from: ["source"] },
      "subject" => { from: ["subject"], parsed: true },
      "title" => { from: ["title"] },
      "resource_type" => { from: ["type"], parsed: true },
      "remote_files" => { from: ["thumbnail_url"], parsed: true }
    }
  }
end
```

## Configuring Import Work Types

An Import needs to know what Work Type to create. The importer looks for:

1) An incoming metadata field mapped to 'model'
2) An incoming metadata field mapped to 'work_type'

If it does not find either of these, or the data they contain is not a valid Work Type in the repository, the `default_work_type` will be used.

The install generator sets `default_work_type` to the first Work Type returned by `Hyrax.config.curation_concerns` but this can be overriden by setting `default_work_type` in `config/initializer/bulkrax.rb` as shown above.

## Configuring Field Mapping

It's unlikely that the incoming import data has fields that exactly match those in your repository. Field mappings allow you to tell bulkrax how to map field in the incoming data to a field in your application.

By default, the 

## How it Works
Once you have Bulkrax installed, you will have access to an easy to use interface with which you are able to create, edit, delete, run, and re-run imports and exports. 

Imports can be scheduled to run once or on a daily, monthly or yearly interval. 

Import and export is available to admins via the Importers tab on the dashboard. Export currently supports CSV only.

### View List of Importers
From the admin dashboard, select the "Importers" tab. You will see a list of previously created importers with details of last run, next run, number of records enqueued and processed, failures, deleted upstream records, and total records. From this page you can create a new importer, edit an importer or delete an importer.

### View List of Exporters
From the admin dashboard, select the "Exporters" tab. You will see a list of previously created exporters with details of last run, number of records enqueued and processed, failures, deleted upstream records, and total records. From this page you can create a new exporter, edit an exporter or delete an exporter.

### Create an Importer or Exporter
To create a new importer, select the "New" button on the Importers or Exporters page and complete the form. Name and, for Importer, Administrative set are required. When you select a parser, you will see a set of specific fields to complete.

### Edit an Importer or Exporter
To edit an importer or exporter, select the edit icon (pencil) and complete the form.

### Delete and Importer or Exporter
To delete an importer or exporter, select the delete (x) icon.

### Downloading an export
Once your the exporter has run, a download icon will apear on the exporters menu page.

## Contributing
See
[CONTRIBUTING.md](https://github.com/samvera-labs/bulkrax/blob/master/CONTRIBUTING.md)
for contributing guidelines.

We encourage everyone to help improve this project.  Bug reports and pull requests are welcome on GitHub at https://github.com/samvera-labs/bulkrax.

This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

All Contributors should have signed the Hydra Contributor License Agreement (CLA)

## Questions
Questions can be sent to support@notch8.com. Please make sure to include "Bulkrax" in the subject line of your email.


## License
The gem is available as open source under the terms of the [Apache 2.0 License](https://opensource.org/licenses/Apache-2.0).

