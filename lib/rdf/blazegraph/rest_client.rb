module RDF::Blazegraph
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
    # Deletes all statements from the server
    def clear_statements
      send_delete_request('')
    end

    ##
    # Send a request to the server
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
    # @raise [ArugmentError] when a statement is invalid
    # @todo handle blank nodes
    def insert(statements)
      sts = statements.lazy.map do |st|
        raise ArgumentError, "Invalid statement #{st}" if 
          st.respond_to?(:invalid?) && st.invalid?
        st
      end

      send_post_request(url, sts)
      return self
    end

    ##
    # @param [RDF::Enumerable] statements
    #
    # @todo handle blank nodes
    def delete(statements)
      return self if statements.empty?

      statements.map! do |s| 
        statement = RDF::Statement.from(s).dup
        statement.graph_name ||= NULL_GRAPH_URI 
        statement
      end

      if statements.count == 1 && !statements.first.has_blank_nodes?
        st = statements.first
        query = access_path_query(st.subject, st.predicate, st.object, st.graph_name)
        send_delete_request(query)
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

    ##
    # @param [RDF::Enumerable<RDF::Statement>, Array<RDF::Statement>] dels
    # @param [RDF::Enumerable<RDF::Statement>, Array<RDF::Statement>] ins
    #
    # @return [RDF::Blazegraph::RestClient] self
    def delete_insert(deletes, ins)
      delete(deletes)
      insert(ins)
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
      writer = RDF::Writer.for(:nquads)
      
      request = Net::HTTP::Post.new(request_url)
      request['Content-Type'] = 'text/x-nquads'
      request.body = writer.dump(statements)
      
      @http.request(url, request)
    end

    def send_delete_request(query)
      query = "#{query[1..-1]}" if query.start_with? '&'
      request = Net::HTTP::Delete.new(url + "?#{::URI::encode(query)}")
      
      @http.request(url, request)
    end

    ## 
    # @param [Net::HTTPResponse] response
    # @return [RDF::Enumerable]
    def read_rdf_response(response)
      RDF::Reader.for(content_type: 'application/n-quads').new(response.body)
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
