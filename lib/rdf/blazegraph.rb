require 'rdf'
require 'sparql/client'
require 'rexml/document'
require 'net/http/persistent'

module RDF
  ##
  # An RDF::Repository implementaton for Blazegraph (formerly BigData).
  #
  # @todo support context
  #
  # @see RDF::Repository
  # @see http://wiki.blazegraph.com
  class Blazegraph
    VOCAB_BD = RDF::Vocabulary.new('http://www.bigdata.com/rdf#')
    NULL_GRAPH_URI = Blazegraph::VOCAB_BD.nullGraph

    class Repository < SPARQL::Client::Repository
      ##
      # @return [RDF::Blazegraph::RestClient]
      def rest_client
        @rest_client = Blazegraph::RestClient.new(@client.url)
      end

      ##
      # @see RDF::Enumerable#count
      def count
        rest_client.fast_range_count
      end

      ##
      # @see RDF::Repository#each
      def each(&block)
        rest_client.get_statements.each_statement(&block)
      end

      ##
      # @see RDF::Repository#empty?
      def empty?
        !rest_client.has_statement?
      end

      ##
      # @see RDF::Repository#has_predicate?
      def has_context?(context)
        rest_client.has_statement?(context: context)
      end

      ##
      # @see RDF::Repository#has_predicate?
      def has_predicate?(predicate)
        rest_client.has_statement?(predicate: predicate)
      end

      ##
      # @see RDF::Repository#has_object?
      def has_object?(object)
        return super if object.node?
        rest_client.has_statement?(object: object)
      end

      ##
      # @see RDF::Repository#has_triple?
      def has_triple?(triple)
        return super unless triple.find(&:node?).nil?
        rest_client.has_statement?(subject:   triple[0],
                                   predicate: triple[1],
                                   object:    triple[2])
      end

      ##
      # Calls the Blazegraph API unless a blank node is present, in which case we 
      # fall back on SPARQL ASK.
      # @see RDF::Repostiory#has_statement?
      def has_statement?(statement)
        has_quad?(statement)
      end

      ##
      # @see RDF::Repository#has_subject?
      def has_subject?(subject)
        return super if subject.node?
        rest_client.has_statement?(subject: subject)
      end

      ##
      # @see RDF::Repository#has_subject?
      def has_quad?(statement)
        statement = RDF::Statement.from(statement)
        rest_client.has_statement?(subject:   statement.subject,
                                   predicate: statement.predicate,
                                   object:    statement.object,
                                   context:   statement.context)
      end

      ##
      # @see SPARQL::Client::Repository#supports?
      def supports?(feature)
        return true if feature.to_sym == :context
        super
      end

      protected

      ##
      # Deletes the given RDF statements from the underlying storage.
      #
      # Overridden here to use SPARQL/UPDATE
      #
      # @param  [RDF::Enumerable] statements
      # @return [void]
      def delete_statements(statements)
        @rest_client.delete(statements)
      end

      ##
      # Queries `self` for RDF statements matching the given `pattern`.
      #
      # @todo: handle quads
      # @see SPARQL::Client::Repository#query_pattern
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
        
        unless where_pattern.context.nil?
          where_pattern.context ||= NULL_GRAPH_URI
          query.graph(where_pattern.context)
          query.filter("#{where_pattern.context} != #{NULL_GRAPH_URI.to_base}") if
            where_pattern.context.variable?
        end

        if block_given?
          query.each_statement(&block)
        else
          query.solutions.to_a.extend(RDF::Enumerable, RDF::Queryable)
        end
      end

      def insert_statements(statements)
        rest_client.insert(statements)
      end

      def insert_statement(statement)
        rest_client.insert([statement])
      end
    end
    ##
    # A wrapper for the NanoSparqlServer REST API. This implements portions of 
    # the API that are not parts of SPARQL; such as optimized queries like 
    # FastRangeCount.
    #
    # @see https://wiki.blazegraph.com/wiki/index.php/REST_API NanoSparqlServer 
    #   REST documentation
    class RestClient
      attr_reader :url

      ##
      # @param [#to_s] uri  a uri identifying the Blazegraph API endpoint; e.g.
      #   `http://localhost:9999/bigdata/sparql`
      def initialize(url)
        @http = Net::HTTP::Persistent.new(self.class)
        @url = URI(url.to_s)
        @sparql_client = SPARQL::Client.new(@url)
      end

      ##
      # Send a request to the server
      #
      # @todo handle POST requests
      #
      # @param [String] query
      #
      # @return [Net::HTTP::Response] the server's response
      # @raise [RequestError] if the request returns a non-success response code
      def execute(query)
        response = @http.request(url + ::URI::encode(query))

        return response if response.is_a? Net::HTTPSuccess
        raise RequestError.new("#{response.code}: #{response.body}\n" \
                               "Processing query #{query}") 
      end

      ##
      # Returns a count of the number of triples in the datastore.
      #
      # We use the `exact` option, to ensure that counts are exact regardless
      # of sharding and other configuration conditions.
      #
      # Errors are thrown if a bnode is given for any of the terms or if a 
      # literal is given in the subject or predicate place.
      #
      # @param [Boolean] exact  whether to insist on an exact range count, or 
      #   allow approximations e.g. across multiple shards; default: `true`
      #
      # @return [Integer] the count of triples matching the query
      #
      # @raise [RequestError] if the request is invalid or the server throws an 
      #   error
      def fast_range_count(subject: nil, predicate: nil, object: nil, 
                           context: nil, exact: true)
        st_query = access_path_query(subject, predicate, object, context)
        resp = execute("?ESTCARD#{st_query}&exact=#{exact}")
        read_xml_response(resp, :rangeCount).to_i
      end

      ##
      # Returns statements matching the given pattern.
      # 
      # Errors are thrown if a bnode is given for any of the terms or if a 
      # literal is given in the subject or predicate place.
      # 
      # @param [Boolean] include_inferred  includes inferred triples if `true', 
      #   default: `false`
      # 
      # @return [RDF::Enumerable] statements parsed from the server response
      #
      # @raise [RequestError] if the request is invalid or the server throws an 
      #   error
      def get_statements(subject: nil, predicate: nil, object: nil, 
                         context: nil, include_inferred: false)
        st_query = access_path_query(subject, predicate, object, context)
        query = "?GETSTMTS#{st_query}&include_inferred=#{include_inferred}"
        read_rdf_response(execute(query))
      end

      ##
      # Checks for existence of a statement matching the pattern.
      #
      # Errors are thrown if a bnode is given for any of the terms or if a 
      # literal is given in the subject or predicate place.
      #
      # @param [Boolean] include_inferred  includes inferred triples if `true', 
      #   default: `false`
      # 
      # @return [Boolean] true if statement matching the pattern exists
      #
      # @raise [RequestError] if the request is invalid or the server throws an 
      #   error
      def has_statement?(subject: nil, predicate: nil, object: nil, 
                         context: nil, include_inferred: false)
        if [subject, predicate, object].compact.find(&:node?)
          sparql_ask_statement([subject, predicate, object], context)
        else
          st_query = access_path_query(subject, predicate, object, context)
          query = "?HASSTMT#{st_query}&include_inferred=#{include_inferred}"

          read_boolean_response(execute(query))
        end
      end

      ##
      # @param [RDF::Enumerable] statements
      #
      # @todo handle blank nodes
      def insert(statements)
        send_post_request(url, statements)
        return self
      end

      ##
      # @param [RDF::Enumerable] statements
      #
      # @todo handle blank nodes
      def delete(statements)
        return self if statements.empty?

        statements.map! do |s| 
          statement = RDF::Statement.from(s)
          statement.context ||= NULL_GRAPH_URI 
          statement
        end

        constant = statements.all? do |statement|
          !statement.respond_to?(:each_statement) && statement.constant? && 
            !statement.has_blank_nodes?
        end

        if constant
          send_post_request(url + '?delete', statements)
        else
          # delete with blank nodes
        end

        return self
      end

      private

      def sparql_ask_statement(triple, context)
        triple.map! do |term|
          unless term.nil?
            term.node? ? RDF::Query::Variable.new(term.id) : term
          end
        end

        query = @sparql_client.ask.where(triple)
        query.graph(context) if context
        triple.each do |term| 
          query.filter("isBlank(#{term})") if !term.nil? && term.variable?
        end

        query.true?
      end
      
      def send_post_request(request_url, statements)
        io = StringIO.new
        writer = RDF::Writer.for(:nquads)
        
        io.rewind

        request = Net::HTTP::Post.new(request_url)
        request['Content-Type'] = 
          RDF::Writer.for(:nquads).format.content_type.last # use text/x-nquads
        request.body = writer.dump(statements)
        
        @http.request(url, request)
      end
      
      ## 
      # @param [Net::HTTPResponse] response
      # @return [RDF::Enumerable]
      def read_rdf_response(response)
        RDF::Reader.for(content_type: response.content_type).new(response.body)
      end

      ## 
      # @param [Net::HTTPResponse] response
      # @return [RDF::Enumerable]
      def read_boolean_response(response)
        read_xml_response(response, :result) == 'true' ? true : false
      end

      ## 
      # @param [Net::HTTPResponse] response
      # @param [Net::HTTPResponse] attr
      # @return [RDF::Enumerable]
      def read_xml_response(response, attr)
        REXML::Document.new(response.body).root.attribute(attr).value
      end

      ##
      # @param [RDF::URI, RDF::Literal] subject
      # @param [RDF::URI, RDF::Literal] predicate
      # @param [RDF::URI, RDF::Literal] object
      # @param [RDF::URI, RDF::Literal] context
      #
      # @return [String] a query string for "Access Path Operations"
      #
      # @todo: fail fast when given a literal predicate or a bnode? Currently we
      #   try the request on Blazegraph and handle the Net::HTTP response.
      #
      # @see https://wiki.blazegraph.com/wiki/index.php/REST_API#Access_Path_Operations
      def access_path_query(subject, predicate, object, context)
        str = {s: subject, p: predicate, o: object, c: context}.map do |k, v|
          v ? "#{k}=#{v.to_base}" : nil
        end.compact.join('&')
        str.empty? ? str : "&#{str}" 
      end

      public

      ##
      # An error class to capture non-succesful RestClient responses
      class RequestError < RuntimeError; end
    end
  end
end
