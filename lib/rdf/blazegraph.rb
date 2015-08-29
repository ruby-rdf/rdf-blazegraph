require 'rdf'
require 'sparql/client'
require 'rexml/document'
require 'net/http/persistent'

module RDF
  ##
  # This module bundles tools for working with Blazegraph using RDF.rb.
  #
  # @see http://ruby-rdf.github.io
  # @see http://wiki.blazegraph.com
  module Blazegraph
    VOCAB_BD = RDF::Vocabulary.new('http://www.bigdata.com/rdf#')
    NULL_GRAPH_URI = Blazegraph::VOCAB_BD.nullGraph
    
    autoload :Repository, 'rdf/blazegraph/repository'
    autoload :RestClient, 'rdf/blazegraph/rest_client'
  end
end
