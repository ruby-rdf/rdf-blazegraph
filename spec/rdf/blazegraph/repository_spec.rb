require 'spec_helper'
require 'rdf/spec/repository'

describe RDF::Blazegraph::Repository do
  let(:endpoint) { 'http://localhost:9999/bigdata/sparql' }

  before { RDF::Blazegraph::Repository.new('http://localhost:9999/bigdata/sparql').clear! }

  # @see lib/rdf/spec/repository.rb
  let(:repository) { RDF::Blazegraph::Repository.new(endpoint) }
  it_behaves_like 'an RDF::Repository'
end

