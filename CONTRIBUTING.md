# Contributing to Bulkrax

We encourage everyone to help improve this project.  Bug reports and pull requests are welcome on GitHub at https://github.com/samvera-labs/bulkrax.

This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](https://contributor-covenant.org) code of conduct.

All Contributors should have signed the Hydra Contributor License Agreement (CLA)

## Reporting Issues

The preferred way to submit bug reports is to submit an issue at https://github.com/samvera-labs/bulkrax/issues


## Contributing Code

If you would like to contribute code for this project, you can submit your pull request at https://github.com/samvera-labs/bulkrax/pulls


## Write, Clarify, or Fix Documentation

If you would like to contribute to the documentation for this project, you can submit your pull request at https://github.com/samvera-labs/bulkrax/pulls


## Suggest or add new features

The preferred way to submit feature requests is to submit an issue at https://github.com/samvera-labs/bulkrax/issues


## Questions

Questions can be sent to support@notch8.com. Please make sure to include "Bulkrax" in the subject line of your email.


## Running the spec suite
### Set up the test database
``` bash
bundle exec rake db:create
bundle exec rake db:migrate
bundle exec rake bin/rails db:migrate RAILS_ENV=test
```

### Run the specs
```
bundle exec rake (all specs)
bundle exec rspec (all specs)
bundle exec rspec <path-to-file> (single file)
```

## Running rubocop
```
bundle exec rubocop -a <path-to-file> (single file)
```
# Thank You!

Thank you for your interest in contributing to Bulkrax.  We appreciate you for taking the time to contribute.
