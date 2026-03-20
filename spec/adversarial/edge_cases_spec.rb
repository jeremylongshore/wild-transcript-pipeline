# frozen_string_literal: true

RSpec.describe 'Edge cases' do
  describe 'Configuration edge cases' do
    it 'supports multiple custom patterns simultaneously' do
      WildTranscriptPipeline.configure do |c|
        c.custom_patterns = [/PATTERN_A/, /PATTERN_B/]
      end
      redactor = WildTranscriptPipeline::Privacy::Redactor.new
      result = redactor.redact_content('has PATTERN_A and PATTERN_B',
                                       config: WildTranscriptPipeline.configuration)
      expect(result).not_to include('PATTERN_A')
      expect(result).not_to include('PATTERN_B')
    end

    it 'supports very low intent threshold (0.0)' do
      WildTranscriptPipeline.configure { |c| c.intent_confidence_threshold = 0.0 }
      detector = WildTranscriptPipeline::Normalization::IntentDetector.new
      turns = [make_turn(role: :user, content: 'I need to do something')]
      intents = detector.detect(turns, config: WildTranscriptPipeline.configuration)
      expect(intents).not_to be_empty
    end

    it 'supports very high threshold (1.0) producing no intents for normal text' do
      WildTranscriptPipeline.configure { |c| c.intent_confidence_threshold = 1.0 }
      detector = WildTranscriptPipeline::Normalization::IntentDetector.new
      turns = [make_turn(role: :user, content: 'I need to do something')]
      intents = detector.detect(turns, config: WildTranscriptPipeline.configuration)
      expect(intents).to be_empty
    end

    it 'reset_configuration! restores all defaults' do
      WildTranscriptPipeline.configure { |c| c.redaction_marker = '***' }
      WildTranscriptPipeline.reset_configuration!
      expect(WildTranscriptPipeline.configuration.redaction_marker).to eq('[REDACTED]')
    end
  end

  describe 'Turn edge cases' do
    it 'allows empty string content' do
      t = WildTranscriptPipeline::Models::Turn.new(role: :user, content: '')
      expect(t.content).to eq('')
    end

    it 'handles content with newlines and special chars' do
      content = "Line 1\nLine 2\t\rLine 3"
      t = WildTranscriptPipeline::Models::Turn.new(role: :user, content: content)
      expect(t.content).to eq(content)
    end

    it 'handles unicode content' do
      content = '日本語テスト 🚀 emoji'
      t = WildTranscriptPipeline::Models::Turn.new(role: :user, content: content)
      expect(t.content).to eq(content)
    end
  end

  describe 'TurnNormalizer edge cases' do
    let(:normalizer) { WildTranscriptPipeline::Normalization::TurnNormalizer.new }

    it 'handles single-character content at the exact limit' do
      WildTranscriptPipeline.configure { |c| c.max_turn_content_length = 1 }
      turns = [make_turn(content: 'a')]
      result = normalizer.normalize(turns, config: WildTranscriptPipeline.configuration)
      expect(result.first.content).to eq('a')
    end

    it 'truncates at exact limit boundary' do
      WildTranscriptPipeline.configure { |c| c.max_turn_content_length = 5 }
      turns = [make_turn(content: 'abcdef')]
      result = normalizer.normalize(turns, config: WildTranscriptPipeline.configuration)
      expect(result.first.content).to eq('abcde')
    end
  end

  describe 'ToolExtractor edge cases' do
    let(:extractor) { WildTranscriptPipeline::Normalization::ToolExtractor.new }

    it 'handles turns with no content gracefully' do
      turns = [make_turn(role: :assistant, content: '')]
      expect(extractor.extract(turns)).to be_empty
    end

    it 'handles multiple mcp:// references in one turn' do
      content = 'Use mcp://tool_a and mcp://tool_b together'
      turns = [make_turn(role: :assistant, content: content)]
      refs = extractor.extract(turns)
      names = refs.map(&:name)
      expect(names).to include('tool_a', 'tool_b')
    end

    it 'assigns correct indices across multiple turns' do
      turns = [
        make_turn(role: :user, content: 'Check routes'),
        make_turn(role: :assistant, content: '[tool_use] inspect_routes({})'),
        make_turn(role: :tool, content: '[tool_result:inspect_routes] 42 routes')
      ]
      refs = extractor.extract(turns)
      indices = refs.map(&:turn_index).uniq.sort
      expect(indices).to all(be >= 0)
    end
  end

  describe 'IntentDetector edge cases' do
    let(:detector) { WildTranscriptPipeline::Normalization::IntentDetector.new }

    it 'handles turns array with system turns' do
      turns = [make_turn(role: :system, content: 'I need to configure everything')]
      intents = detector.detect(turns)
      expect(intents).to be_empty
    end

    it 'handles very long turn content' do
      content = "I need to #{' do something ' * 500}now"
      turns = [make_turn(role: :user, content: content)]
      expect { detector.detect(turns) }.not_to raise_error
    end
  end

  describe 'Export edge cases' do
    let(:json_exporter) { WildTranscriptPipeline::Export::JsonExporter.new }
    let(:md_exporter) { WildTranscriptPipeline::Export::MarkdownExporter.new }

    it 'JSON exporter handles transcript with many tool references' do
      refs = 20.times.map do |i|
        make_tool_reference(name: "tool_#{i}", turn_index: i)
      end
      t = make_transcript(tool_references: refs)
      output = json_exporter.export([t])
      parsed = JSON.parse(output)
      expect(parsed['transcripts'].first['tool_reference_count']).to eq(20)
    end

    it 'Markdown exporter handles transcript with many intents' do
      intents = 10.times.map do |i|
        make_intent(description: "Intent #{i}", source_turn_index: i)
      end
      t = make_transcript(intents: intents)
      output = md_exporter.export([t])
      expect(output).to include('Intent 0')
      expect(output).to include('Intent 9')
    end

    it 'Markdown exporter handles turns with special markdown characters' do
      turn = make_turn(content: '**bold** and _italic_ and `code` and [link](url)')
      t = make_transcript(turns: [turn])
      expect { md_exporter.export([t]) }.not_to raise_error
    end
  end

  describe 'TranscriptBatch edge cases' do
    it 'handles empty batch for summary counts' do
      batch = WildTranscriptPipeline::Models::TranscriptBatch.new(transcripts: [])
      expect(batch.total_turns).to eq(0)
      expect(batch.total_intents).to eq(0)
      expect(batch.total_tool_references).to eq(0)
      expect(batch.source_types).to be_empty
    end

    it 'computes source_types from mixed adapters' do
      t1 = make_transcript(source_type: :claude_code, source_id: 'a')
      t2 = make_transcript(source_type: :mcp_log, source_id: 'b')
      t3 = make_transcript(source_type: :generic, source_id: 'c')
      batch = WildTranscriptPipeline::Models::TranscriptBatch.new(transcripts: [t1, t2, t3])
      expect(batch.source_types).to match_array(%i[claude_code mcp_log generic])
    end
  end
end
