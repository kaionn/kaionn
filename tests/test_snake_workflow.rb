require 'minitest/autorun'
require_relative '../scripts/check_snake_workflow'

class SnakeWorkflowTest < Minitest::Test
  def fixture
    SnakeWorkflow.load_file(File.expand_path('../.github/workflows/snake.yml', __dir__))
  end

  def test_current_structure_has_only_job_scoped_contents_write
    result = SnakeWorkflow.check(fixture)
    assert_equal 'output', result.fetch(:target_branch)
    assert_equal true, result.fetch(:contents_write_configured)
  end

  def test_candidate_job_scoped_contents_write_is_recognized_in_memory_only
    workflow = fixture
    workflow['jobs']['generate']['permissions'] = { 'contents' => 'write' }
    assert_equal true, SnakeWorkflow.check(workflow).fetch(:contents_write_configured)
  end

  def test_missing_permission_is_reported_without_executing_workflow
    workflow = fixture
    workflow['jobs']['generate'].delete('permissions')
    result = SnakeWorkflow.check(workflow)
    assert_equal false, result.fetch(:contents_write_configured)
    assert_equal false, result.fetch(:execution_verified)
  end

  def test_workflow_wide_write_is_rejected
    ['write-all', { 'contents' => 'write' }].each do |permissions|
      workflow = fixture
      workflow['permissions'] = permissions
      assert_raises(ArgumentError) { SnakeWorkflow.check(workflow) }
    end
  end

  def test_extra_job_permissions_are_rejected
    workflow = fixture
    workflow['jobs']['generate']['permissions'] = { 'contents' => 'write', 'issues' => 'write' }
    assert_raises(ArgumentError) { SnakeWorkflow.check(workflow) }
  end

  def test_privileged_pull_request_trigger_is_rejected
    workflow = fixture
    (workflow['on'] || workflow[true])['pull_request_target'] = {}
    assert_raises(ArgumentError) { SnakeWorkflow.check(workflow) }
  end

  def test_destination_and_token_changes_are_rejected
    workflow = fixture
    workflow['jobs']['generate']['steps'][1]['with']['target_branch'] = 'main'
    assert_raises(ArgumentError) { SnakeWorkflow.check(workflow) }
    workflow = fixture
    workflow['jobs']['generate']['steps'][1]['env']['GITHUB_TOKEN'] = '${{ secrets.OTHER_TOKEN }}'
    assert_raises(ArgumentError) { SnakeWorkflow.check(workflow) }
  end

  def test_additional_token_paths_and_action_fields_are_rejected
    mutations = [
      ->(w) { w['env'] = { 'GH_PAT' => '${{ secrets.OTHER_TOKEN }}' } },
      ->(w) { w['jobs']['generate']['env'] = { 'GH_PAT' => '${{ secrets.OTHER_TOKEN }}' } },
      ->(w) { w['jobs']['generate']['steps'][0]['env'] = { 'GH_PAT' => '${{ secrets.OTHER_TOKEN }}' } },
      ->(w) { w['jobs']['generate']['steps'][0]['with']['github_token'] = '${{ secrets.OTHER_TOKEN }}' },
      ->(w) { w['jobs']['generate']['steps'][1]['with']['token'] = '${{ secrets.OTHER_TOKEN }}' },
      ->(w) { w['jobs']['generate']['steps'][1]['run'] = 'echo changed' }
    ]
    mutations.each do |mutation|
      workflow = fixture
      mutation.call(workflow)
      assert_raises(ArgumentError) { SnakeWorkflow.check(workflow) }
    end
  end

  def test_missing_generator_is_rejected
    workflow = fixture
    workflow['jobs']['generate']['steps'].shift
    assert_raises(ArgumentError) { SnakeWorkflow.check(workflow) }
  end

  def test_invalid_structure_is_rejected
    [nil, [], { 'jobs' => [] }].each do |workflow|
      assert_raises(ArgumentError) { SnakeWorkflow.check(workflow) }
    end
  end
end
