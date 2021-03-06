require 'spec_helper_acceptance'
require 'serverspec_type_zabbixapi'

describe 'zabbix_host type' do
  context 'create zabbix_host resources' do
    it 'runs successfully' do
      # This will deploy a running Zabbix setup (server, web, db) which we can
      # use for custom type tests
      pp = <<-EOS
        class { 'apache':
            mpm_module => 'prefork',
        }
        include apache::mod::php
        include postgresql::server

        class { 'zabbix':
          zabbix_version   => '3.0', # zabbixapi gem doesn't currently support higher versions
          zabbix_url       => 'localhost',
          manage_resources => true,
          require          => [ Class['postgresql::server'], Class['apache'], ],
        }

        Zabbix_host {
          zabbix_user    => 'Admin',
          zabbix_pass    => 'zabbix',
          zabbix_url     => 'localhost',
          apache_use_ssl => false,
          require        => [ Service['zabbix-server'], Package['zabbixapi'], ],
        }

        zabbix_host { 'test1.example.com':
          ipaddress    => '127.0.0.1',
          use_ip       => true,
          port         => 10050,
          group        => 'TestgroupOne',
          group_create => true,
          templates    => [ 'Template OS Linux', ],
        }
        zabbix_host { 'test2.example.com':
          ipaddress    => '127.0.0.2',
          use_ip       => false,
          port         => 1050,
          group        => 'Virtual machines',
          templates    => [ 'Template OS Linux', 'Template ICMP Ping', ],
        }
      EOS

      shell('yum clean metadata') if fact('os.family') == 'RedHat'

      # Cleanup old database
      shell('/opt/puppetlabs/bin/puppet resource service zabbix-server ensure=stopped; /opt/puppetlabs/bin/puppet resource package zabbix-server-pgsql ensure=purged; rm -f /etc/zabbix/.*done; su - postgres -c "psql -c \'drop database if exists zabbix_server;\'"')

      apply_manifest(pp, catch_failures: true)
    end

    let(:result_hosts) do
      zabbixapi('localhost', 'Admin', 'zabbix', 'host.get', selectParentTemplates: ['host'],
                                                            selectInterfaces: %w[dns ip main port type useip],
                                                            selectGroups: ['name'], output: ['host', '']).result
    end

    context 'test1.example.com' do
      let(:test1) { result_hosts.select { |h| h['host'] == 'test1.example.com' }.first }

      it 'is created' do
        expect(test1['host']).to eq('test1.example.com')
      end
      it 'is in group TestgroupOne' do
        expect(test1['groups'].map { |g| g['name'] }).to eq(['TestgroupOne'])
      end
      it 'has a correct interface dns configured' do
        expect(test1['interfaces'][0]['dns']).to eq('test1.example.com')
      end
      it 'has a correct interface ip configured' do
        expect(test1['interfaces'][0]['ip']).to eq('127.0.0.1')
      end
      it 'has a correct interface main configured' do
        expect(test1['interfaces'][0]['main']).to eq('1')
      end
      it 'has a correct interface port configured' do
        expect(test1['interfaces'][0]['port']).to eq('10050')
      end
      it 'has a correct interface type configured' do
        expect(test1['interfaces'][0]['type']).to eq('1')
      end
      it 'has a correct interface useip configured' do
        expect(test1['interfaces'][0]['useip']).to eq('1')
      end
      it 'has templates attached' do
        expect(test1['parentTemplates'].map { |t| t['host'] }.sort).to eq(['Template OS Linux'])
      end
    end

    context 'test2.example.com' do
      let(:test2) { result_hosts.select { |h| h['host'] == 'test2.example.com' }.first }

      it 'is created' do
        expect(test2['host']).to eq('test2.example.com')
      end
      it 'is in group Virtual machines' do
        expect(test2['groups'].map { |g| g['name'] }).to eq(['Virtual machines'])
      end
      it 'has a correct interface dns configured' do
        expect(test2['interfaces'][0]['dns']).to eq('test2.example.com')
      end
      it 'has a correct interface ip configured' do
        expect(test2['interfaces'][0]['ip']).to eq('127.0.0.2')
      end
      it 'has a correct interface main configured' do
        expect(test2['interfaces'][0]['main']).to eq('1')
      end
      it 'has a correct interface port configured' do
        expect(test2['interfaces'][0]['port']).to eq('1050')
      end
      it 'has a correct interface type configured' do
        expect(test2['interfaces'][0]['type']).to eq('1')
      end
      it 'has a correct interface useip configured' do
        expect(test2['interfaces'][0]['useip']).to eq('0')
      end
      it 'has templates attached' do
        expect(test2['parentTemplates'].map { |t| t['host'] }.sort).to eq(['Template ICMP Ping', 'Template OS Linux'])
      end
    end
  end
end
