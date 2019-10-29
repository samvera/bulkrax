# Bulkrax
Bulkrax is a batteries included importer for Samvera applications. It currently includes support for OAIPMH (DC and Qualified DC) and CSV out of the box. It is also designed to be extensible, allowing you to easily add new importers in to your application or to include them with other gems. Bulkrax provides a full admin interface including creating, editing, scheduling and reviewing imports.


## Installation

### Manual Installation

Add this line to your application's Gemfile:

```ruby
gem 'bulkrax', git: 'https://github.com/notch8/bulkrax.git'
```

And then execute:
```bash
$ bundle install
```

Mount the engine in your routes file

```ruby 
mount Bulkrax::Engine, at: '/'
```

Ensure you have queues setup for `import` and `export`

```ruby 
# in config/sidekiq.yml
:queues:
  - default
  - import
	- export
	# other queues
```

```ruby 
# in app/assets/javascripts/application.js - before //= require_tree .
//= require bulkrax/application
```

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

