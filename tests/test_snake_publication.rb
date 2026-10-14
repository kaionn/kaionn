require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require_relative '../scripts/check_snake_workflow'

class SnakePublicationTest < Minitest::Test
  FILES = %w[github-contribution-grid-snake.svg github-contribution-grid-snake-dark.svg].freeze

  def git(*args, dir: @root)
    output, status = Open3.capture2e('git', '-C', dir, *args)
    raise output unless status.success?
    output.strip
  end

  def setup
    @root = Dir.mktmpdir('snake-publication-')
    @remote = File.join(@root, 'remote.git')
    git('init', '--bare', @remote)
    @seed = File.join(@root, 'seed')
    git('init', '--initial-branch=output', @seed)
    git('config', 'user.name', 'Test', dir: @seed)
    git('config', 'user.email', 'test@example.invalid', dir: @seed)
    File.write(File.join(@seed, 'keep.txt'), 'keep')
    FILES.each { |name| File.write(File.join(@seed, name), '<svg>old</svg>') }
    git('add', '.', dir: @seed)
    git('commit', '-m', 'Existing output', dir: @seed)
    git('remote', 'add', 'origin', @remote, dir: @seed)
    git('push', 'origin', 'output', dir: @seed)
    @original = git('rev-parse', 'output', dir: @seed)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def publish(extra: nil, race: false)
    work = Dir.mktmpdir('run-', @root)
    incoming = File.join(work, 'incoming')
    FileUtils.mkdir_p(incoming)
    FILES.each { |name| File.write(File.join(incoming, name), '<svg>new</svg>') }
    File.write(File.join(incoming, 'unexpected.sh'), 'exit 0') if extra
    script = SnakeWorkflow.load_file(File.expand_path('../.github/workflows/snake.yml', __dir__))['jobs']['publish']['steps'][1]['run']
    script = script.sub('"https://github.com/${GITHUB_REPOSITORY}.git"', '"$TEST_REMOTE"')
    if race
      script = script.sub('git push origin HEAD:refs/heads/output', <<~BASH)
        git -C "$TEST_SEED" commit --allow-empty -m Concurrent
        git -C "$TEST_SEED" push origin output
        git push origin HEAD:refs/heads/output
      BASH
    end
    output, status = Open3.capture2e({ 'GITHUB_TOKEN' => 'local-test', 'TEST_REMOTE' => @remote, 'TEST_SEED' => @seed }, 'bash', '-euo', 'pipefail', '-c', script, chdir: work)
    [output, status, work]
  end

  def test_preserves_history_other_files_and_noop
    output, status, work = publish
    assert status.success?, output
    head = git('rev-parse', 'refs/heads/output', dir: @remote)
    assert_equal @original, git('rev-parse', "#{head}^", dir: @remote)
    assert_equal 'keep', git('show', 'output:keep.txt', dir: @remote)
    FILES.each { |name| assert_equal '<svg>new</svg>', git('show', "output:#{name}", dir: @remote) }
    config = File.read(File.join(work, 'publication/.git/config'))
    refute_match(/AUTHORIZATION|extraheader|local-test/, config)
    output, status, = publish
    assert status.success?, output
    assert_equal head, git('rev-parse', 'refs/heads/output', dir: @remote)
  end

  def test_initializes_missing_output
    git('update-ref', '-d', 'refs/heads/output', dir: @remote)
    output, status, = publish
    assert status.success?, output
    assert_equal '1', git('rev-list', '--count', 'output', dir: @remote)
    assert_equal FILES.sort, git('ls-tree', '--name-only', 'output', dir: @remote).lines.map(&:strip).sort
  end

  def test_rejects_extra_artifact_without_changing_remote
    output, status, = publish(extra: true)
    refute status.success?, output
    assert_equal @original, git('rev-parse', 'output', dir: @remote)
  end

  def test_concurrent_external_push_fails_without_overwriting
    output, status, = publish(race: true)
    refute status.success?, output
    assert_equal git('rev-parse', 'output', dir: @seed), git('rev-parse', 'output', dir: @remote)
    assert_equal @original, git('rev-parse', 'output^', dir: @remote)
  end
end
