require 'spec_helper'

describe 'deployment integrations' do
  include IntegrationExampleGroup

  describe 'static drain' do
    it 'runs the drain script on a job if drain script is present' do
      run_bosh("target http://localhost:#{current_sandbox.director_port}")
      run_bosh('login admin admin')

      run_bosh('create release', TEST_RELEASE_DIR)
      run_bosh('upload release', TEST_RELEASE_DIR)

      run_bosh("upload stemcell #{spec_asset('valid_stemcell.tgz')}")

      manifest_hash = Bosh::Spec::Deployments.simple_manifest
      manifest_hash['release']['version'] = 'latest'
      manifest_hash['jobs'][0]['instances'] = 1
      manifest_hash['resource_pools'][0]['size'] = 1

      deployment_manifest = yaml_file('simple', manifest_hash)
      run_bosh("deployment #{deployment_manifest.path}")
      run_bosh('deploy')
      deployment_manifest.delete

      manifest_hash['properties'] ||= {}
      manifest_hash['properties']['test_property'] = 0
      deployment_manifest = yaml_file('simple', manifest_hash)
      run_bosh("deployment #{deployment_manifest.path}")
      run_bosh('deploy')

      drain_output = Dir["#{current_sandbox.agent_tmp_path}/agent-base-dir-*/*"].detect {|f| File.basename(f) == 'drain-test.log' }
      expect(File.read(drain_output)).to eq "job_unchanged hash_changed\n1\n"
    end
  end

  describe 'dynamic drain' do
    it 'retries after the appropriate amount of time' do
      run_bosh("target http://localhost:#{current_sandbox.director_port}")
      run_bosh('login admin admin')

      run_bosh('create release', TEST_RELEASE_DIR)
      run_bosh('upload release', TEST_RELEASE_DIR)

      run_bosh("upload stemcell #{spec_asset('valid_stemcell.tgz')}")

      manifest_hash = Bosh::Spec::Deployments.simple_manifest
      manifest_hash['release']['version'] = 'latest'
      manifest_hash['jobs'][0]['instances'] = 1
      manifest_hash['resource_pools'][0]['size'] = 1
      manifest_hash['properties'] ||= {}
      manifest_hash['properties']['drain_type'] = 'dynamic'

      deployment_manifest = yaml_file('simple', manifest_hash)
      run_bosh("deployment #{deployment_manifest.path}")
      run_bosh('deploy')
      deployment_manifest.delete

      manifest_hash['properties']['test_property'] = 0
      deployment_manifest = yaml_file('simple', manifest_hash)
      run_bosh("deployment #{deployment_manifest.path}")
      run_bosh('deploy')

      drain_output = Dir["#{current_sandbox.agent_tmp_path}/agent-base-dir-*/*"].detect {|f| File.basename(f) == 'drain-test.log' }
      drain_times = File.read(drain_output).split.map { |time| time.to_i }
      drain_times.size.should == 3
      (drain_times[1] - drain_times[0]).should be >= 3
      (drain_times[2] - drain_times[1]).should be >= 2
    end
  end

  context 'updating jobs in parallel' do
    it 'should update a job with multiple instances in parallel and obey max_in_flight' do
      run_bosh("target http://localhost:#{current_sandbox.director_port}")
      run_bosh('login admin admin')

      run_bosh('create release', TEST_RELEASE_DIR)
      run_bosh('upload release', TEST_RELEASE_DIR)

      run_bosh("upload stemcell #{spec_asset('valid_stemcell.tgz')}")

      manifest_hash = Bosh::Spec::Deployments.simple_manifest
      manifest_hash['release']['version'] = 'latest'
      manifest_hash['update']['canaries'] = 0
      manifest_hash['properties'] = {'test_property' => 2}
      manifest_hash['update']['max_in_flight'] = 2

      deployment_manifest = yaml_file('simple', manifest_hash)
      run_bosh("deployment #{deployment_manifest.path}")
      run_bosh('deploy')

      times = start_and_finish_times_for_job_updates('last')
      expect(times['foobar/1']['started']).to be >= times['foobar/0']['started']
      expect(times['foobar/1']['started']).to be < times['foobar/0']['finished']
      expect(times['foobar/2']['started']).to be >= [times['foobar/0']['finished'], times['foobar/1']['finished']].min
    end
  end

  context 'canceling a deploy job' do
    it 'should spawn a job and then successfully cancel it' do
      manifest_hash = Bosh::Spec::Deployments.simple_manifest
      manifest_hash['release']['version'] = 'latest'

      deployment_manifest = yaml_file('simple', manifest_hash)

      run_bosh("target http://localhost:#{current_sandbox.director_port}")
      run_bosh('login admin admin')

      run_bosh('create release', TEST_RELEASE_DIR)
      run_bosh('upload release', TEST_RELEASE_DIR)

      run_bosh("upload stemcell #{spec_asset('valid_stemcell.tgz')}")

      run_bosh("deployment #{deployment_manifest.path}")
      run_result = run_bosh('--no-track deploy')

      task_id = get_task_id(run_result, 'running')

      # If you don't have this sleep, events() will hang
      # And, yes, you need it before "cancel task"
      sleep 5 # Wait for deployment to start
      cancel_result = run_bosh("cancel task #{task_id}")

      expect($?).to be_success
      expect(cancel_result).to match /Task #{task_id} is getting canceled/

      error_event = events(task_id).last['error']
      expect(error_event['code']).to eq(10001)
      expect(error_event['message']).to eq("Task #{task_id} cancelled")
    end
  end
end