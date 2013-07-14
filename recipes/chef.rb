#
# Cookbook Name:: rundeck
# Recipe:: chef
#
# Author:: Panagiotis Papadomitsos (<pj@ezgr.net>)
#
# Copyright 2013, Panagiotis Papadomitsos
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe 'supervisor'

if Chef::Config[:solo]
	adminobj = data_bag_item(node['rundeck']['admin']['data_bag'], node['rundeck']['admin']['data_bag_id']) rescue {
		'client_key' => node['rundeck']['chef']['client_key'],
		'client_name' => node['rundeck']['chef']['client_name']
	}
elsif node['rundeck']['admin']['encrypted_data_bag']
	adminobj = Chef::EncryptedDataBagItem.load(node['rundeck']['admin']['data_bag'], node['rundeck']['admin']['data_bag_id'])
else
	adminobj = data_bag_item(node['rundeck']['admin']['data_bag'], node['rundeck']['admin']['data_bag_id'])
end

if adminobj['client_key'].nil? || adminobj['client_key'].empty? || adminobj['client_name'].nil? || adminobj['client_name'].empty?
	Chef::Log.info('Could not locate a valid client/PEM key pair for chef-rundeck. Please define one!')
	return true
end

# Install the chef-rundeck gem on the Chef omnibus package. Useful workaround instead of installing RVM, a system Ruby etc
# and it offers minimal system pollution
# Currently installing a better version than the original Opscode one, pending a pull request

git "#{Chef::Config['file_cache_path']}/chef-rundeck-gem" do
	repository node['rundeck']['chef']['repo']
	reference node['rundeck']['chef']['reference']
	action :sync
	notifies :install, 'chef_gem[chef-rundeck]'
end

chef_gem 'chef-rundeck' do
	source "#{Chef::Config['file_cache_path']}/chef-rundeck-gem/#{node['rundeck']['chef']['gem_file']}"
	action :nothing
end

# Create the knife.rb for chef-rundeck to read
directory '/var/lib/rundeck/.chef' do
	owner 'rundeck'
	group 'rundeck'
	mode 00755
	action :create
end

template '/var/lib/rundeck/.chef/knife.rb' do
	source 'knife.rb.erb'
	owner 'rundeck'
	group 'rundeck'
	mode 00644
	variables({
		:user => adminobj['client_name'],
		:chef_server_url => Chef::Config['chef_server_url']
	})
	notifies :restart, 'supervisor_service[chef-rundeck]'
end

file "/var/lib/rundeck/.chef/#{adminobj['client_name']}.pem" do
	action :create
	owner 'rundeck'
	group 'rundeck'
	mode 00644
	content adminobj['client_key']
end

# Create a Supervisor service that runs chef-rundeck
supervisor_service 'chef-rundeck' do
	command "/opt/chef/embedded/bin/chef-rundeck -c /var/lib/rundeck/.chef/knife.rb -l -u #{node['rundeck']['ssh']['user']} -w #{Chef::Config['chef_server_url'].sub(':4000',':4040')} -p #{node['rundeck']['chef']['port']} -s #{node['rundeck']['ssh']['port']}"
	numprocs 1
	directory '/var/lib/rundeck'
	autostart true
	autorestart :unexpected
	startsecs 15
	stopwaitsecs 15
	stdout_logfile 'NONE'
	stopsignal :TERM
	user 'rundeck'
	redirect_stderr true
	action :enable
end
