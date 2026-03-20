# frozen_string_literal: true

RSpec.describe 'Full pipeline integration' do
  let(:normalizer) { WildTranscriptPipeline::Normalization::TurnNormalizer.new }
  let(:intent_detector) { WildTranscriptPipeline::Normalization::IntentDetector.new }
  let(:tool_extractor) { WildTranscriptPipeline::Normalization::ToolExtractor.new }
  let(:redactor) { WildTranscriptPipeline::Privacy::Redactor.new }
  let(:json_exporter) { WildTranscriptPipeline::Export::JsonExporter.new }
  let(:md_exporter) { WildTranscriptPipeline::Export::MarkdownExporter.new }

  describe 'Claude Code session pipeline' do
    let(:jsonl) { claude_code_jsonl }
    let(:adapter) { WildTranscriptPipeline::Ingestion::ClaudeCodeAdapter.new }

    it 'completes ingest -> normalize -> redact -> export without error' do
      transcripts = adapter.parse(jsonl, source_id: 'session-001')
      normalized = transcripts.map { |t| normalizer.normalize(t.turns) }
      redacted = normalized.map { |turns| turns.map { |turn| redactor.redact_turn(turn) } }
      expect(redacted).not_to be_empty
    end

    it 'produces valid JSON output' do
      transcripts = WildTranscriptPipeline.process(jsonl, adapter: adapter, source_id: 'session-001')
      json = json_exporter.export(transcripts)
      parsed = JSON.parse(json)
      expect(parsed['summary']['transcript_count']).to eq(1)
    end

    it 'produces non-empty markdown output' do
      transcripts = WildTranscriptPipeline.process(jsonl, adapter: adapter)
      md = md_exporter.export(transcripts)
      expect(md).to include('# Transcript Export')
      expect(md).to include('### Turns')
    end

    it 'detects tool references for tool_use entries' do
      transcripts = WildTranscriptPipeline.process(jsonl, adapter: adapter)
      all_refs = transcripts.flat_map(&:tool_references)
      expect(all_refs.map(&:name)).to include('inspect_connection')
    end
  end

  describe 'MCP log pipeline' do
    let(:json) { mcp_log_json }
    let(:adapter) { WildTranscriptPipeline::Ingestion::McpLogAdapter.new }

    it 'ingests and processes MCP logs' do
      transcripts = WildTranscriptPipeline.process(json, adapter: adapter, source_id: 'mcp-001')
      expect(transcripts).to all(be_a(WildTranscriptPipeline::Models::Transcript))
    end

    it 'produces exportable JSON' do
      transcripts = WildTranscriptPipeline.process(json, adapter: adapter)
      output = json_exporter.export(transcripts)
      expect { JSON.parse(output) }.not_to raise_error
    end

    it 'detects tool references from MCP requests' do
      transcripts = WildTranscriptPipeline.process(json, adapter: adapter)
      all_refs = transcripts.flat_map(&:tool_references)
      expect(all_refs).not_to be_empty
    end
  end

  describe 'Generic conversation pipeline' do
    let(:json) { generic_json }
    let(:adapter) { WildTranscriptPipeline::Ingestion::GenericAdapter.new }

    it 'processes generic conversations end to end' do
      transcripts = WildTranscriptPipeline.process(json, adapter: adapter)
      expect(transcripts).not_to be_empty
    end

    it 'strips sensitive content in generic conversations' do
      turns = [
        { 'role' => 'user', 'content' => 'My email is secret@corp.com' },
        { 'role' => 'assistant', 'content' => 'Got it' }
      ]
      input = JSON.generate({ 'turns' => turns })
      transcripts = WildTranscriptPipeline.process(input, adapter: adapter)
      content_values = transcripts.flat_map(&:turns).map(&:content)
      expect(content_values.join).not_to include('secret@corp.com')
    end
  end

  describe 'Batch export' do
    it 'exports multiple transcripts as a batch' do
      batch = make_transcript_batch(count: 3)
      json = json_exporter.export_batch(batch)
      parsed = JSON.parse(json)
      expect(parsed['summary']['transcript_count']).to eq(3)
    end
  end

  describe 'WildTranscriptPipeline.process convenience method' do
    it 'returns Transcript objects' do
      adapter = WildTranscriptPipeline::Ingestion::GenericAdapter.new
      result = WildTranscriptPipeline.process(generic_json, adapter: adapter)
      expect(result).to all(be_a(WildTranscriptPipeline::Models::Transcript))
    end

    it 'marks transcripts as processed' do
      adapter = WildTranscriptPipeline::Ingestion::GenericAdapter.new
      result = WildTranscriptPipeline.process(generic_json, adapter: adapter)
      expect(result.first.metadata[:processed]).to be(true)
    end

    it 'applies custom config' do
      adapter = WildTranscriptPipeline::Ingestion::GenericAdapter.new
      WildTranscriptPipeline.configure do |c|
        c.max_turns_per_transcript = 1
      end
      result = WildTranscriptPipeline.process(generic_json, adapter: adapter,
                                                            config: WildTranscriptPipeline.configuration)
      expect(result.first.turn_count).to be <= 1
    end
  end
end
