require 'spec_helper'

describe RDF::Blazegraph do
  it 'has a vocab' do
    expect(described_class::VOCAB_BD).to be_a RDF::Vocabulary
  end

  it 'has a null graph URI' do
    expect(described_class::NULL_GRAPH_URI).to be_a RDF::URI
  end
end
