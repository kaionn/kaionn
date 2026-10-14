require 'yaml'
require 'json'
require 'digest'

module SnakeWorkflow
  PINS = %w[
    Platane/snk/svg-only@d8f6715049803e982ee5ff501b6b9b7d5deeb09b
    actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
    actions/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093
  ].freeze

  def self.load_file(file)
    YAML.safe_load(File.read(file), permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def self.require_condition(condition, message)
    raise ArgumentError, message unless condition
  end

  def self.check(w)
    require_condition(w.is_a?(Hash), 'workflow must be a mapping')
    require_condition((w.keys - ['name', 'on', true, 'permissions', 'concurrency', 'jobs']).empty?, 'unexpected workflow field')
    events = w['on'] || w[true]
    require_condition(events == { 'schedule' => [{ 'cron' => '0 0 * * *' }], 'workflow_dispatch' => nil, 'push' => { 'branches' => ['main'] } }, 'triggers must remain unchanged')
    require_condition(w['permissions'] == {}, 'default permissions must be empty')
    require_condition(w['concurrency'] == { 'group' => 'snake-output', 'cancel-in-progress' => false }, 'publishes must serialize without cancellation')
    jobs = w['jobs']
    require_condition(jobs.is_a?(Hash) && jobs.keys.sort == %w[generate publish], 'only generate and publish are allowed')
    generate, publish = jobs.values_at('generate', 'publish')
    require_condition(generate['permissions'] == {}, 'generation must have no repository permissions')
    require_condition(publish['permissions'] == { 'contents' => 'write' }, 'only publication may write contents')
    require_condition(publish['needs'] == 'generate' && publish['if'] == "github.ref == 'refs/heads/main'", 'publication requires successful main generation')
    [generate, publish].each do |job|
      require_condition(job['runs-on'] == 'ubuntu-latest' && job['timeout-minutes'] == 10, 'runner and timeout changed')
      require_condition((job.keys - %w[runs-on timeout-minutes permissions steps needs if]).empty?, 'unexpected job field')
    end
    g, u = generate['steps']
    d, p = publish['steps']
    require_condition(generate['steps'].size == 2 && publish['steps'].size == 2, 'unexpected steps')
    require_condition([g['uses'], u['uses'], d['uses']] == PINS, 'Actions must match reviewed full SHAs')
    require_condition(g.keys.sort == %w[name uses with] && g['with'] == {
      'github_user_name' => '${{ github.repository_owner }}',
      'outputs' => "dist/github-contribution-grid-snake.svg\ndist/github-contribution-grid-snake-dark.svg?palette=github-dark\n"
    }, 'unexpected generator inputs')
    require_condition(u.keys.sort == %w[name uses with] && u['with'] == {
      'name' => 'snake-svg', 'path' => "dist/github-contribution-grid-snake.svg\ndist/github-contribution-grid-snake-dark.svg\n",
      'if-no-files-found' => 'error', 'retention-days' => 1
    }, 'upload only the two SVGs')
    require_condition(d.keys.sort == %w[name uses with] && d['with'] == { 'name' => 'snake-svg', 'path' => 'incoming' }, 'download only this run artifact')
    require_condition(p.keys.sort == %w[env name run shell] && p['shell'] == 'bash' && p['env'] == { 'GITHUB_TOKEN' => '${{ github.token }}' }, 'unexpected publisher fields or credential')
    script = p['run']
    require_condition(Digest::SHA256.hexdigest(script) == '2e966278d3d4eb296d66df8de3ef4021c3cb5354ca545e6bd43f7faba4a72f4f', 'publisher script must match the reviewed implementation')
    require_condition(script.include?('git fetch --no-tags origin refs/heads/output') && script.include?('git checkout -B output FETCH_HEAD'), 'retain existing output ancestry')
    require_condition(script.include?('git push origin HEAD:refs/heads/output') && !script.match?(/--force|\+HEAD|--orphan|eval\b|source\b/), 'publication must not force push or execute artifact code')
    require_condition(script.include?('git add -- "${files[@]}"') && script.include?('test ! -L "incoming/$file"'), 'stage only regular allowlisted files')
    { target_branch: 'output', generation_permissions: {}, publication_permissions: { contents: 'write' }, execution_verified: false }
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    puts JSON.generate(SnakeWorkflow.check(SnakeWorkflow.load_file('.github/workflows/snake.yml')))
  rescue ArgumentError, Psych::Exception => error
    warn error.message
    exit 1
  end
end
