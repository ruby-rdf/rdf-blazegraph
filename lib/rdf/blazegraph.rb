require 'rdf'
require 'sparql/client'
require 'rexml/document'
require 'net/http/persistent'

module RDF
  class Blazegraph < SPARQL::Client::Repository
    
    def initialize(*)
      result = super
    end

    def blazegraph_client
      @blazegraph_client = Client.new(@client.url)
    end

    def count
      blazegraph_client.fast_range_count
    end

    ##
    # Queries `self` for RDF statements matching the given `pattern`.
    #
    # @example
    #     repository.query([nil, RDF::DOAP.developer, nil])
    #     repository.query(:predicate => RDF::DOAP.developer)
    #
    # @fixme This should use basic SPARQL query mechanism.
    #
    # @param  [Pattern] pattern
    # @see    RDF::Queryable#query_pattern
    # @yield  [statement]
    # @yieldparam [Statement]
    # @return [Enumerable<Statement>]
    def query_pattern(pattern, &block)
      pattern = pattern.dup
      pattern.subject   ||= RDF::Query::Variable.new
      pattern.predicate ||= RDF::Query::Variable.new
      pattern.object    ||= RDF::Query::Variable.new
      pattern.initialize!

      # Blazegraph objects to bnodes shared across the CONSTRUCT & WHERE scopes
      # so we dup the pattern with fresh bnodes
      where_pattern = pattern.dup
      where_pattern.subject = RDF::Node.new if where_pattern.subject.node?
      where_pattern.predicate = RDF::Node.new if where_pattern.predicate.node?
      where_pattern.object = RDF::Node.new if where_pattern.object.node?
      where_pattern.initialize!

      query = client.construct(pattern).where(where_pattern)

      if block_given?
        query.each_statement(&block)
      else
        query.solutions.to_a.extend(RDF::Enumerable, RDF::Queryable)
      end
    end

    
    
  end

  class Client
    attr_reader :url

    def initialize(url)
      @http = Net::HTTP::Persistent.new
      @url = URI(url.to_s)
    end
    
    def fast_range_count
      resp = @http.request(url + '?ESTCARD')
      REXML::Document.new(resp.body).root.attribute(:rangeCount).value.to_i
    end
  end
end
