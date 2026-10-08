require 'yaml'
require 'json'

module SnakeWorkflow
  def self.load_file(file)
    YAML.safe_load(File.read(file), permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def self.require_condition(condition, message)
    raise ArgumentError, message unless condition
  end

  def self.check(workflow)
    require_condition(workflow.is_a?(Hash), 'workflow must be a mapping')
    require_condition((workflow.keys - ['name', 'on', true, 'jobs', 'permissions']).empty?, 'additional workflow fields are prohibited')
    events_keys = ['on', true].select { |key| workflow.key?(key) }
    require_condition(events_keys.length == 1, 'one unambiguous event mapping is required')
    events = workflow[events_keys.first]
    require_condition(events.is_a?(Hash) && events.keys.sort == %w[push schedule workflow_dispatch], 'only the existing main/schedule/manual triggers are allowed')
    require_condition(events['push'].is_a?(Hash) && events['push']['branches'] == ['main'], 'push must target main')
    require_condition(events['schedule'] == [{ 'cron' => '0 0 * * *' }], 'schedule must remain unchanged')
    require_condition([nil, {}].include?(events['workflow_dispatch']), 'manual inputs must remain unchanged')

    require_condition([nil, {}, { 'contents' => 'read' }].include?(workflow['permissions']), 'workflow-wide write permission is prohibited')
    jobs = workflow['jobs']
    require_condition(jobs.is_a?(Hash) && jobs.keys == ['generate'], 'only the existing generate job is allowed')
    job = jobs['generate']
    require_condition(job.is_a?(Hash), 'generate must be a mapping')
    require_condition((job.keys - ['runs-on', 'timeout-minutes', 'steps', 'permissions']).empty?, 'additional job fields are prohibited')
    require_condition(job['runs-on'] == 'ubuntu-latest' && job['timeout-minutes'] == 10, 'runner and timeout must remain unchanged')
    permissions = job['permissions']
    require_condition([nil, {}, { 'contents' => 'read' }, { 'contents' => 'write' }].include?(permissions), 'only job-scoped contents permission is allowed')
    steps = job['steps']
    require_condition(steps.is_a?(Array) && steps.length == 2 && steps.all? { |step| step.is_a?(Hash) }, 'two existing action steps are required')
    generator, publish = steps
    require_condition((generator.keys - ['name', 'uses', 'with']).empty? && (publish.keys - ['name', 'uses', 'with', 'env']).empty?, 'additional action fields are prohibited')
    require_condition(generator['uses'] == 'Platane/snk/svg-only@v3', 'generator action must remain unchanged')
    generator_inputs = generator['with']
    require_condition(generator_inputs.is_a?(Hash) && generator_inputs['github_user_name'] == '${{ github.repository_owner }}', 'generator owner must remain unchanged')
    require_condition(generator_inputs.keys.sort == %w[github_user_name outputs], 'additional generator inputs are prohibited')
    outputs = generator_inputs['outputs']
    require_condition(outputs.is_a?(String) && outputs.lines.map(&:strip).reject(&:empty?) == [
      'dist/github-contribution-grid-snake.svg',
      'dist/github-contribution-grid-snake-dark.svg?palette=github-dark'
    ], 'only the existing SVG outputs are allowed')
    require_condition(publish['uses'] == 'crazy-max/ghaction-github-pages@v4', 'publish action must remain unchanged')
    require_condition(publish['with'].is_a?(Hash) && publish['with']['target_branch'] == 'output' && publish['with']['build_dir'] == 'dist', 'publish destination must remain output/dist')
    require_condition(publish['with'].keys.sort == %w[build_dir target_branch], 'additional publish inputs are prohibited')
    require_condition(publish['env'] == { 'GITHUB_TOKEN' => '${{ secrets.GITHUB_TOKEN }}' }, 'only the existing Actions token is allowed')
    {
      target_branch: 'output',
      contents_write_configured: permissions == { 'contents' => 'write' },
      execution_verified: false
    }
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
