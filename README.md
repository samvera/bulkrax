# Bulkrax
Short description and motivation.

## Usage
How to use my plugin.

## Installation
Add this line to your application's Gemfile:

```ruby
gem 'bulkrax'
```

And then execute:
```bash
$ bundle
```

Mount the engine in your routes file

```ruby 
mount Bulkrax::Engine, at: '/'
```

Install the migrations

```bash
rails bulkrax:install:migrations db:migrate
```

## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
