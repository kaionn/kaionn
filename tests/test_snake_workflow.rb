require 'minitest/autorun'
require_relative '../scripts/check_snake_workflow'

class SnakeWorkflowTest < Minitest::Test
  def fixture
    SnakeWorkflow.load_file(File.expand_path('../.github/workflows/snake.yml', __dir__))
  end

  def test_permissions_are_separated
    result = SnakeWorkflow.check(fixture)
    assert_equal({}, result[:generation_permissions])
    assert_equal({ contents: 'write' }, result[:publication_permissions])
    assert_equal false, result[:execution_verified]
  end

  def test_unsafe_changes_are_rejected
    mutations = [
      ->(w) { w['jobs']['publish']['steps'][1]['run'] += "bash ../incoming/github-contribution-grid-snake.svg\n" },
      ->(w) { w['permissions'] = { 'contents' => 'write' } },
      ->(w) { w['jobs']['generate']['permissions'] = { 'contents' => 'read' } },
      ->(w) { w['jobs']['publish']['permissions']['actions'] = 'write' },
      ->(w) { w['concurrency']['cancel-in-progress'] = true },
      ->(w) { (w['on'] || w[true])['pull_request_target'] = nil },
      ->(w) { w['jobs']['publish'].delete('needs') },
      ->(w) { w['jobs']['publish'].delete('if') },
      ->(w) { w['jobs']['generate']['steps'][0]['uses'] = 'Platane/snk/svg-only@v3' },
      ->(w) { w['jobs']['generate']['steps'][1]['with']['path'] = 'dist' },
      ->(w) { w['jobs']['publish']['steps'][0]['with']['run-id'] = '123' },
      ->(w) { w['jobs']['publish']['steps'][1]['env']['GITHUB_TOKEN'] = '${{ secrets.PAT }}' },
      ->(w) { w['jobs']['publish']['steps'][1]['run'].sub!('git push origin', 'git push --force origin') },
      ->(w) { w['jobs']['publish']['steps'][1]['run'].sub!('git fetch --no-tags', 'git fetch') },
      ->(w) { w['jobs']['publish']['steps'] << { 'run' => 'incoming/code.sh' } }
    ]
    mutations.each do |mutate|
      w = fixture
      mutate.call(w)
      assert_raises(ArgumentError) { SnakeWorkflow.check(w) }
    end
  end
end
