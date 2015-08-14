require 'spec_helper'
require 'rdf/spec/repository'

describe RDF::Blazegraph do
  subject { RDF::Blazegraph.new(endpoint) }
  let(:endpoint) { 'http://localhost:9999/bigdata/sparql' }

  before { RDF::Blazegraph.new('http://localhost:9999/bigdata/sparql').clear! }

  # @see lib/rdf/spec/repository.rb
  let(:repository) { RDF::Blazegraph.new(endpoint) }
  it_behaves_like 'an RDF::Repository'
end
