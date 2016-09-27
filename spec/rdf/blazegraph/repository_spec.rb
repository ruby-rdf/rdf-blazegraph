require 'spec_helper'
require 'rdf/spec/repository'

describe RDF::Blazegraph::Repository do
  let(:endpoint) { 'http://127.0.0.1:9999/blazegraph/sparql' }

  before { RDF::Blazegraph::Repository.new(uri: endpoint).clear! }

  # @see lib/rdf/spec/repository.rb
  let(:repository) { RDF::Blazegraph::Repository.new(uri: endpoint) }
  it_behaves_like 'an RDF::Repository'
end

