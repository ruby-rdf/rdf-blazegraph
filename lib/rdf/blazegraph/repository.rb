require 'sparql/client'

module RDF::Blazegraph
  ##
  # An RDF::Repository implementaton for Blazegraph (formerly BigData).
  #
  # @see RDF::Repository
  class Repository < SPARQL::Client::Repository
    ##
    # @return [RDF::Blazegraph::RestClient]
    def rest_client
      @rest_client = RestClient.new(@client.url)
    end

    ##
    # @see RDF::Enumerable#count
    def count
      rest_client.fast_range_count
    end

    ##
    # @see RDF::Mutable#delete_insert
    def delete_insert(deletes, inserts)
      rest_client.delete_insert(deletes, inserts)
    end

    ##
    # @see RDF::Repository#each
    # @todo this won't scale
    def each(&block)
      rest_client.get_statements.each_statement(&block)
    end

    ##
    # @see RDF::Repository#empty?
    def empty?
      !rest_client.has_statement?
    end

    ##
    # @see RDF::Repository#has_graph_name?
    def has_graph?(graph_name)
      rest_client.has_statement?(context: graph_name)
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
                                 context:   statement.graph_name)
    end

    ##
    # @see SPARQL::Client::Repository#supports?
    def supports?(feature)
      return true if feature.to_sym == :context
      return true if feature.to_sym == :graph_name
      super
    end

    protected

    ##
    # @private
    # @see RDF::Mutable#clear
    def clear_statements
      rest_client.clear_statements
    end

    ##
    # Deletes the given RDF statements from the underlying storage.
    #
    # Overridden here to use the Blazegraph REST client
    #
    # @param  [RDF::Enumerable] statements
    # @return [void]
    def delete_statements(statements)
      rest_client.delete(statements)
    end

    ##
    # Queries `self` for RDF statements matching the given `pattern`.
    #
    # @see SPARQL::Client::Repository#query_pattern
    def query_pattern(pattern, options = {}, &block)
      pattern = pattern.dup
      pattern.subject   ||= RDF::Query::Variable.new
      pattern.predicate ||= RDF::Query::Variable.new
      pattern.object    ||= RDF::Query::Variable.new
      pattern.initialize!

      return fast_pattern(pattern, &block) unless 
        pattern.subject.node? || pattern.predicate.node? || pattern.object.node?

      # Blazegraph objects to bnodes shared across the CONSTRUCT & WHERE scopes
      # so we dup the pattern with fresh bnodes
      where_pattern = pattern.dup
      where_pattern.subject = RDF::Node.new if where_pattern.subject.node?
      where_pattern.predicate = RDF::Node.new if where_pattern.predicate.node?
      where_pattern.object = RDF::Node.new if where_pattern.object.node?
      where_pattern.initialize!

      query = client.construct(pattern).where(where_pattern)
      
      unless where_pattern.graph_name.nil?
        where_pattern.graph_name ||= NULL_GRAPH_URI
        query.graph(where_pattern.graph_name)
        query.filter("#{where_pattern.graph_name} != #{NULL_GRAPH_URI.to_base}") if
          where_pattern.graph_name.variable?
      end

      if block_given?
        query.each_statement(&block)
      else
        query.solutions.to_a.extend(RDF::Enumerable, RDF::Queryable)
      end
    end

    def fast_pattern(pattern, &block)
      pattern = pattern.dup
      pattern.graph_name = NULL_GRAPH_URI if pattern.graph_name == false

      reader = 
        rest_client.get_statements(subject: variable_to_nil(pattern.subject),
                                   predicate: variable_to_nil(pattern.predicate),
                                   object: variable_to_nil(pattern.object),
                                   context: variable_to_nil(pattern.graph_name))

      return reader.each_statement(&block) if block_given?
      reader.each_statement
    end

    def insert_statements(statements)
      rest_client.insert(statements)
    end

    def insert_statement(statement)
      rest_client.insert([statement])
    end

    def variable_to_nil(term)
      return nil unless term
      term.variable? ? nil : term
    end
  end
end
