require 'spec_helper'
require 'rdf/vocab'

describe RDF::Blazegraph::RestClient do
  subject { described_class.new(endpoint) }
  let(:endpoint) { 'http://localhost:9999/bigdata/sparql' }
  let(:repository) { RDF::Blazegraph::Repository.new(endpoint) }

  let(:statements) do
    [ RDF::Statement(RDF::URI('http://ex.org/moomin'), 
                     RDF::Vocab::DC.title, 
                     'moomin'), 
      RDF::Statement(RDF::URI('http://ex.org/moomin'), 
                     RDF::Vocab::DC.relation, 
                     RDF::Node.new) ]
  end

  before { repository.clear! }
  
  describe '#fast_range_count' do
    it 'changes when statements are added' do
      expect { repository.insert(*statements) }
        .to change { subject.fast_range_count }.from(0).to(statements.count)
    end
  end

  describe '#delete' do
    before { subject.insert(statements) }
    
    it 'deletes triple' do
      expect { subject.delete([statements.first]) }
        .to change { subject.fast_range_count }.from(2).to(1)
    end

    it 'deletes with blank node' do
      expect { subject.delete([statements.last]) }
        .to change { subject.get_statements }
             .to(contain_exactly(statements.first))
    end

    context 'with graph name' do
      before { subject.insert([with_graph_name]) }

      let(:with_graph_name) do
        RDF::Statement(RDF::URI('http://ex.org/snorkmaiden'), 
                       RDF::Vocab::DC.description,
                       'Snorkmaiden',
                       graph_name: RDF::URI('http://ex.org/snork'))
      end

      it 'does not delete statement with missing graph name' do
        with_graph_name.graph_name = nil

        expect { subject.delete([with_graph_name]) }
          .not_to change { subject.get_statements.to_a }
      end

      it 'does not delete statement with mismatched graph name' do
        with_graph_name.graph_name = RDF::URI('http://ex.org/wrong_graph')

        expect { subject.delete([with_graph_name]) }
          .not_to change { subject.get_statements.to_a }
      end

      it 'deletes correct graph name' do
        expect { subject.delete([with_graph_name]) }
          .to change { subject.fast_range_count }.by(-1)
      end

      context 'with bnode' do
        it 'deletes correct statements' do
          statement = statements[1]
          statement.graph_name = RDF::URI('http://ex.org/new_context')
          
          statement_no_node = statement.clone
          statement_no_node.object = RDF::Literal('snork!')
          
          subject.insert([statement, statement_no_node])

          expect { subject.delete([statement, with_graph_name]) }
            .to change { subject.fast_range_count }.by(-2)
          expect(subject.has_statement?(context: with_graph_name.graph_name))
            .to be false
          expect(subject.has_statement?(subject:   statement_no_node.subject,
                                        predicate: statement_no_node.predicate,
                                        object:    statement_no_node.object,
                                        context:   statement_no_node.graph_name))
            .to be true
        end
      end
    end
      
  end

  describe '#get_statements' do
    before { repository.insert(*statements) }

    its(:get_statements) { is_expected.to be_a RDF::Enumerable }

    it 'returns empty when no matches are found' do
      expect(subject.get_statements(object: RDF::Literal('oops'))).to be_empty
    end

    it 'returns correct statements' do
      expected = RDF::Graph.new.insert(*statements)
      actual = RDF::Graph.new << subject.get_statements

      expect(actual).to be_isomorphic_with expected
    end

    it 'matches subject pattern' do
      rdf_subject = statements.first.subject

      expected = RDF::Graph.new
                 .insert(*statements.select { |st| st.subject == rdf_subject })
      actual = RDF::Graph.new << subject.get_statements(subject: rdf_subject)

      expect(actual).to be_isomorphic_with expected
    end

    it 'matches predicate' do
      matches = statements.select do |st| 
        st.predicate == statements.first.predicate
      end

      expect(subject.get_statements(predicate: statements.first.predicate))
        .to contain_exactly(*matches)
    end

    it 'matches object' do
      expect(subject.get_statements(object: statements.first.object))
        .to contain_exactly(statements.first)
    end

    it 'raises an error when given a bnode' do
      expect { subject.get_statements(subject: RDF::Node.new) }
        .to raise_error described_class::RequestError
    end
    
    it 'raises an error when given a literal for subject' do
      expect { subject.get_statements(subject: RDF::Literal('oops')) }
        .to raise_error described_class::RequestError
    end

    it 'raises an error when given a literal for predicate' do
      expect { subject.get_statements(predicate: RDF::Literal('oops')) }
        .to raise_error described_class::RequestError
    end
  end

  describe '#has_statement?' do
    its(:has_statement?) { is_expected.to be false }

    context 'with statements' do
      before { repository.insert(*statements) }

      its(:has_statement?) { is_expected.to be true }

      it 'returns false when there is no match' do
        expect(subject.has_statement?(subject: RDF::OWL.Thing)).to be false
      end
      
      it 'matches subject pattern' do
        expect(subject.has_statement?(subject: statements.first.subject))
          .to be true
      end

      it 'matches predicate pattern' do
        expect(subject.has_statement?(predicate: statements.first.predicate))
          .to be true
      end

      it 'matches object pattern' do
        expect(subject.has_statement?(object: statements.first.object))
          .to be true
      end

      it 'matches partial pattern' do
        expect(subject.has_statement?(subject: statements.first.subject,
                                      predicate: statements.first.predicate))
          .to be true
      end

      it 'does not match when only some properties match ' do
        expect(subject.has_statement?(subject: statements.first.subject,
                                      predicate: statements.first.predicate,
                                      object: RDF::OWL.Thing))
          .to be false
      end

      it 'matches bnodes' do
        expect(subject.has_statement?(subject: RDF::Node.new)).to be false
        expect(subject.has_statement?(object: RDF::Node.new)).to be true
      end

      it 'raises an error on with literal predicate' do
        expect { subject.has_statement?(predicate: RDF::Literal('oops')) }
          .to raise_error described_class::RequestError
      end
    end
  end
  
  describe '#insert' do
    it 'inserts triples' do
      expect { subject.insert(statements) }
        .to change { RDF::Graph.new << subject.get_statements.to_a }
             .to(be_isomorphic_with(RDF::Graph.new.insert(*statements)))
    end

    it 'inserts with graph name' do
      statement = statements.first
      
      statement.graph_name = RDF::URI('http://ex.org/name')
      
      expect { subject.insert([statement]) }
        .to change { subject.has_statement?(subject:   statement.subject,
                                            predicate: statement.predicate,
                                            object:    statement.object,
                                            context:   statement.graph_name) }
             .to be true
    end

    it 'raises an error if not given a collection' do
      expect { subject.insert(statements.first) }.to raise_error NoMethodError
    end

    it 'raises an error if given non-statements' do
      expect { subject.insert(['blah']) }.to raise_error ArgumentError
    end
  end
end
