RDF::Blazegraph
================

An RDF::Repository implementation for [Blazegraph](http://blazegraph.com); a REST client for [NanoSparqlServer](https://wiki.blazegraph.com/wiki/index.php/NanoSparqlServer).

## Usage

Run `gem install rdf-blazegraph` or add `gem 'rdf-blazegraph'` to your Gemspec.

```ruby
require 'rdf/blazegraph'

# as an RDF::Repository
repo = RDF::Blazegraph::Repository.new('http://localhost:9999/bigdata/sparql')
repo << RDF::Statement(RDF::URI('http://example.org/#moomin'), RDF::FOAF.name, 'Moomin')
repo.count # => 1

# with REST interface
nano = RDF::Blazegraph::RestClient.new('http://localhost:9999/bigdata/sparql')
nano.get_statements.each { |s| puts s.inspect }
# #<RDF::Statement:0x3ff0d450e5ec(<http://example.org/#moomin> <http://xmlns.com/foaf/0.1/name> "Moomin" .)>
```

## Running the Tests

```bash
$ bundle install
$ bundle exec rspec
```

## Contributing

This repository uses [Git Flow](https://github.com/nvie/gitflow) to mange development and release activity. All submissions _must_ be on a feature branch based on the _develop_ branch to ease staging and integration.

* Do your best to adhere to the existing coding conventions and idioms.
* Don't use hard tabs, and don't leave trailing whitespace on any line.
  Before committing, run `git diff --check` to make sure of this.
* Do document every method you add using YARD annotations. Read the
  [tutorial][YARD-GS] or look at the existing code for examples.
* Don't touch the `.gemspec` or `VERSION` files. If you need to change them,
  do so on your private branch only.
* Do feel free to add yourself to the `CREDITS` file and the
  corresponding list in the the `README`. Alphabetical order applies.
* Don't touch the `AUTHORS` file. If your contributions are significant
  enough, be assured we will eventually add you in there.
* Do note that in order for us to merge any non-trivial changes (as a rule
  of thumb, additions larger than about 15 lines of code), we need an
  explicit [public domain dedication][PDD] on record from you.

## License

This is free and unencumbered public domain software. For more information,
see <http://unlicense.org/> or the accompanying {file:UNLICENSE} file.
