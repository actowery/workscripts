require 'json'
require 'pp'
require 'csv'
require 'yaml'
require 'beaker-hostgenerator/generator'
require 'net/http'

PE_FAMILY = ENV['PE_FAMILY'] || '2019.8.x'
JENKINS_INSTANCE = 'https://cinext-jenkinsmaster-enterprise-prod-1.delivery.puppetlabs.net'
#NIGHTLY_VIEW = "view/pe-integration/view/pe-#{PE_FAMILY}"
WEEKEND_VIEW = "view/pe-integration/view/pe-#{PE_FAMILY}"
API_PARAMS = 'tree=jobs[displayName,url,color,lastBuild[url],lastFailedBuild[url],activeConfigurations[name,url,color]]'
TEST_RESULT_API_TREE = 'tree=failCount,passCount,skipCount,suites[cases[className,name,skipped,status,duration,skippedMessage]]'

module Job

end

module Cell

end

module Build

end


def get_jenkins_json(view)
  url  = URI.parse(JENKINS_INSTANCE)
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true

  api_url  = "#{url.path}/#{view}/api/json?#{API_PARAMS}"
  puts api_url
  response = http.request(Net::HTTP::Get.new(api_url))
  if response.kind_of?(Net::HTTPSuccess)
    JSON.parse(response.body)
  else
    {}
  end
end

def get_test_results(cell_url)
  url = "#{cell_url}/lastSuccessfulBuild/testReport"
  url = URI.parse(url)
  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true

  api_url  = "#{url.path}/api/json?#{TEST_RESULT_API_TREE}"
  response = http.request(Net::HTTP::Get.new(api_url))
  if response.kind_of?(Net::HTTPSuccess)
    JSON.parse(response.body)
  else
    {}
  end
end

def get_topology(hosts)
  topology = ''

  hosts.values.each do |host|
    template = host['template']
    if !template
      puts "no template option for #{job_name}: #{name}"
      next
    end

    host_roles = host['roles'].sort
    if host_roles == ['master','dashboard','database','agent'].sort
      topology = 'mono'
    elsif host_roles == ['agent','frictionless'].sort
      topology = 'frictionless_agent'
    elsif host_roles == ['agent'].sort
      topology = 'agent'
    elsif host_roles == ['agent', 'master'].sort
      topology = 'split'
    elsif host_roles == ['agent', 'dashboard'].sort
      topology = 'split'
    elsif host_roles == ['agent', 'database'].sort
      topology = 'split'
    elsif host_roles == ['agent', 'legacy_agent'].sort
      topology = 'legacy_agent'
    elsif host_roles.include?('compile_master')
      topology = 'lei'
    elsif host_roles.include?('hub')
      topology = 'lei'
    elsif host_roles.include?('spoke')
      topology = 'lei'
    else
      topology = "unknown #{host_roles}"
    end
  end

  topology
end

genconfig_options = {
  list_platforms_and_roles: false,
  disable_default_role: false,
  disable_role_config: false,
  osinfo_version: 0,
  hypervisor: 'vmpooler',
}


#nightly_json = get_jenkins_json(NIGHTLY_VIEW)
weekend_json = get_jenkins_json(WEEKEND_VIEW)
puts(WEEKEND_VIEW)
puts(weekend_json)
#jobs = nightly_json['jobs'] + weekend_json['jobs']
jobs = weekend_json['jobs']
jobs_with_configs = jobs.select { |h| h.has_key?('activeConfigurations') }

platforms = {}
jobs = {}
total_vms = 0



jobs_with_configs.each do |job|
  job_name = job['displayName']
  configs = job['activeConfigurations']
  next if job['color'] == 'disabled'
  puts "getting information for #{job_name}"

  configs.each do |config|
    next if config['color'] == 'disabled'
    incremented_split_count = false

    name = config['name']
    options = Hash[*CSV.parse(name.gsub('=',',')).flatten]
    layout = options['LAYOUT']
    if layout.nil? || layout.downcase == 'default'
      puts "#{job_name} layout is nil"
      next
    end

    if layout.downcase =~ /aix|sparc/
      puts "#{job_name} is aix or sparc, skipping"
      next
    end

    if layout.downcase =~ /mono|lei/
      puts "ha job, skipping"
      next
    end

    if layout =~ /^[0-9]/
      layout = "#{options['PLATFORM']}-#{layout}"
    end

    if layout =~ /^(centos7|oracle7|redhat7|scientific7|sles12)/
      layout.gsub!('32','64')
    end

    upgrade_ver = options['UPGRADE_FROM']

#   test_results = get_test_results(config['url'])
#   skipped_tests = []
#   not_skipped_tests = []
#   if !test_results.empty?
#     test_results['suites'].each do |suite|
#       suite['cases'].each do |test_case|
    #         test_name = "#{test_case['className']}/#{test_case['name']}"
#         if test_case['skipped']
#           skipped_tests << test_name
#         else
#           not_skipped_tests << test_name
#         end
#       end
#     end
#   end

    hosts = YAML.load(BeakerHostGenerator::Generator.new.generate(layout,genconfig_options).to_yaml)['HOSTS']
    hosts.values.each do |host|
      template = host['template']
      if !template
        puts "no template option for #{job_name}: #{name}"
        next
      end
      platforms[template] ||= {
        'count' => 0,
        'install' => {},
        'upgrade' => {}
      }

      host_roles = host['roles']
      if host_roles.sort == ['master','dashboard','database','agent'].sort
        type = 'mono'
      elsif host_roles.sort == ['agent','frictionless'].sort
        type = 'frictionless_agent'
      elsif host_roles.sort == ['agent'].sort
        type = 'agent'
      elsif host_roles.sort == ['agent', 'master'].sort
        type = 'split'
      elsif host_roles.sort == ['agent', 'dashboard'].sort
        type = 'split'
      elsif host_roles.sort == ['agent', 'database'].sort
        type = 'split'
      elsif host_roles.sort == ['agent', 'legacy_agent'].sort
        type = 'legacy_agent'
      elsif host_roles.include?('compile_master')
        type = 'lei_compile_master'
      elsif host_roles.include?('hub')
        type = 'lei_amq_hub'
      elsif host_roles.include?('spoke')
        type = 'lei_amq_spoke'
      else
        type = "unknown #{host_roles}"
      end

      if upgrade_ver == 'NONE'
        platforms[template]['install'][type] ||= {
          'vm_count'        => 0,
          'times_tested' => 0,
          'jobs'         => [],
        }
        platforms[template]['install'][type]['vm_count'] += 1
#        platforms[template]['install'][type]['skipped_tests'] ||= []
#        platforms[template]['install'][type]['not_skipped_tests'] ||= []
#        platforms[template]['install'][type]['skipped_tests'] += skipped_tests
#        platforms[template]['install'][type]['not_skipped_tests'] += not_skipped_tests
#        platforms[template]['install'][type]['skipped_tests'].uniq!
#        platforms[template]['install'][type]['not_skipped_tests'].uniq!
        platforms[template]['install'][type]['jobs'] |= [job_name]
        if type == 'split' && incremented_split_count == false
          platforms[template]['install'][type]['times_tested'] += 1
          incremented_split_count = true
        elsif type != 'split'
          platforms[template]['install'][type]['times_tested'] += 1
        end
      else
        platforms[template]['upgrade'][type] ||= {}
        platforms[template]['upgrade'][type][upgrade_ver] ||= {
          'vm_count'        => 0,
          'times_tested' => 0,
          'jobs'         => [],
        }
        platforms[template]['upgrade'][type][upgrade_ver]['vm_count'] += 1
#        platforms[template]['upgrade'][type][upgrade_ver]['skipped_tests'] ||= []
#        platforms[template]['upgrade'][type][upgrade_ver]['not_skipped_tests'] ||= []
#        platforms[template]['upgrade'][type][upgrade_ver]['skipped_tests'] += skipped_tests
#        platforms[template]['upgrade'][type][upgrade_ver]['not_skipped_tests'] += not_skipped_tests
#        platforms[template]['upgrade'][type][upgrade_ver]['skipped_tests'].uniq!
#        platforms[template]['upgrade'][type][upgrade_ver]['not_skipped_tests'].uniq!
        platforms[template]['upgrade'][type][upgrade_ver]['jobs'] |= [job_name]
        if type == 'split' && incremented_split_count == false
          platforms[template]['upgrade'][type][upgrade_ver]['times_tested'] += 1
          incremented_split_count = true
        elsif type != 'split'
          platforms[template]['upgrade'][type][upgrade_ver]['times_tested'] += 1
        end
      end

      platforms[template]['count'] += 1
      total_vms += 1
    end
  end
end

File.open("/s/tmp.json","w") do |f|
    f.write(platforms.to_json)
end


puts "Total number of VMs: #{total_vms}"
#puts JSON.pretty_generate(platforms.sort)
