#!/usr/bin/env ruby -rubygems
# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.version            = File.read('VERSION').chomp
  gem.date               = File.mtime('VERSION').strftime('%Y-%m-%d')

  gem.name               = 'rdf-blazegraph'
  gem.homepage           = 'http://ruby-rdf.github.com/'
  gem.license            = 'Public Domain' if gem.respond_to?(:license=)
  gem.summary            = 'A Blazegraph Repository adapter for RDF.rb'
  gem.description        = 'A Blazegraph Repository adapter for RDF.rb'

  gem.authors            = ['Tom Johnson']
  gem.email              = 'public-rdf-ruby@w3.org'

  gem.platform           = Gem::Platform::RUBY
  gem.files              = %w(AUTHORS README.md UNLICENSE VERSION) + Dir.glob('lib/**/*.rb')
  gem.require_paths      = %w(lib app)
  gem.has_rdoc           = false

  gem.required_ruby_version      = '>= 1.9.2'
  gem.requirements               = []

  gem.add_runtime_dependency     'rdf', '~> 1.99'
  gem.add_runtime_dependency     'sparql-client', '~>1.1'

  gem.add_development_dependency 'rdf-spec',    '~> 1.1', '>= 1.1.13'
  gem.add_development_dependency 'rspec',       '~> 3.0'
  gem.add_development_dependency 'rspec-its',   '~> 1.0'
  gem.add_development_dependency 'yard',        '~> 0.8'

  gem.post_install_message       = nil
end
