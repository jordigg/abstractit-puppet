class puppet::master (
  $puppet_env_repo = 'https://bitbucket.org/pivitptyltd/puppet-environments',
  $hiera_repo = 'https://bitbucket.org/pivitptyltd/puppet-hieradata',
  $host = $::hostname,
  $node_ttl = '0s',
  $node_purge_ttl = '0s',
  $report_ttl = '14d',
  $reports = true,
  $unresponsive = '2',
  $env_basedir = '/etc/puppet/environments',
  $hieradata_path = '/etc/puppet/hiera',
  $hiera_yaml_path = '/etc/puppet/hiera/%{environment}',
  $hiera_gpg_path = '/etc/puppet/hiera/%{environment}',
  $r10k_update = true,
  $cron_minutes = ['0','15','30','45'],
  $env_owner = 'puppet',
) {

  include site::monit::apache

  # r10k setup
  package { 'r10k':
    ensure   => '1.2.0',
    provider => gem,
  }
  file { '/etc/r10k.yaml':
    ensure  => file,
    content => template('puppet/r10k.yaml.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }
  ini_setting { 'R10k manifest':
    ensure  => present,
    path    => "${::settings::confdir}/puppet.conf",
    section => 'master',
    setting => 'manifest',
    value   => "${env_basedir}/\$environment/manifests/site.pp",
  }
  file { $env_basedir:
    ensure => directory,
    owner  => 'puppet',
    group  => 'puppet',
    mode   => '0755',
  }
  # cron for updating the r10k environment
  # will possibly link thins to a git commit hook at some point
  cron_job { 'puppet_r10k':
    enable   => $r10k_update,
    interval => 'd',
    script   => "# created by puppet
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${cron_minutes} * * * * ${env_owner} /usr/local/bin/r10k deploy environment
",
  }

  ## setup hiera
  package { 'gpgme':
    ensure   => '2.0.2',
    provider => gem,
  }

  package { 'hiera-gpg':
    ensure   => '1.1.0',
    provider => gem,
  }

  file { '/etc/hiera.yaml':
    ensure  => file,
    content => template('puppet/hiera.yaml.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Vcsrepo['/etc/puppet/hieradata'],
  }
  file { '/etc/puppet/hiera.yaml':
    ensure   => link,
    target   => '/etc/hiera.yaml',
    require  => File['/etc/hiera.yaml'],
  }

  vcsrepo { '/etc/puppet/hieradata':
    ensure   => latest,
    revision => 'production',
    provider => git,
    owner    => puppet,
    group    => puppet,
    source   => 'https://bitbucket.org/pivitptyltd/puppet-hieradata',
  }

  # setup puppetdb
  class { 'puppetdb':
    ssl_listen_address => '0.0.0.0',
    node_ttl           => $node_ttl,
    node_purge_ttl     => $node_purge_ttl,
    report_ttl         => $report_ttl,
  }
  class { 'puppetdb::master::config':
    puppet_service_name     => 'httpd',
    puppetdb_server         => $host,
    enable_reports          => $reports,
    manage_report_processor => $reports,
    restart_puppet          => false,
  }

  ## setup puppetboard
  class { 'python':
    dev        => true,
    pip        => true,
    virtualenv => true,
  }
  class { 'apache':
  }
  class { 'apache::mod::wsgi':
  }
  class { 'puppetboard':
  }
  class { 'puppetboard::apache::vhost':
    vhost_name => 'pboard',
  }

  # passenger settings
  class { 'apache::mod::passenger':
    passenger_high_performance   => 'On',
    passenger_max_pool_size      => '12',
    passenger_pool_idle_time     => '1500',
    passenger_stat_throttle_rate => '120',
    rack_autodetect              => 'Off',
    rails_autodetect             => 'Off',
  }

  package { 'puppetmaster-passenger':
    ensure => installed
  }

  ## puppetmaster vhost in apache
  apache::vhost{ 'puppetmaster':
    docroot           => '/usr/share/puppet/rack/puppetmasterd/public/',
    docroot_owner     => 'root',
    docroot_group     => 'root',
    port              => '8140',
    ssl               => true,
    ssl_protocol      => '-ALL +SSLv3 +TLSv1',
    ssl_cipher        => 'ALL:!ADH:RC4+RSA:+HIGH:+MEDIUM:-LOW:-SSLv2:-EXP',
    ssl_cert          => "/var/lib/puppet/ssl/certs/${host}.pem",
    ssl_key           => "/var/lib/puppet/ssl/private_keys/${host}.pem",
    ssl_chain         => '/var/lib/puppet/ssl/certs/ca.pem',
    ssl_ca            => '/var/lib/puppet/ssl/certs/ca.pem',
    ssl_crl           => '/var/lib/puppet/ssl/ca/ca_crl.pem',
    ssl_certs_dir     => undef,
    ssl_verify_client => 'optional',
    ssl_verify_depth  => '1',
    ssl_options       => ['+StdEnvVars','+ExportCertData'],
    rack_base_uris    => ['/'],
    directories       => [
      { path          => '/usr/share/puppet/rack/puppetmasterd/',
        options       => 'None',
        order         => 'allow,deny',
        allow         => 'from all',
      }
    ],
    request_headers   => [
      'unset X-Forwarded-For',
      'set X-SSL-Subject %{SSL_CLIENT_S_DN}e',
      'set X-Client-DN %{SSL_CLIENT_S_DN}e',
      'set X-Client-Verify %{SSL_CLIENT_VERIFY}e',
    ],
  }

/*
  # environments
  package { 'librarian-puppet':
    ensure   => '0.9.13',
    provider => gem,
  }

  file { '/etc/puppet/environments':
    ensure => directory,
    owner  => 'puppet',
    group  => 'puppet',
    mode   => '0755',
  }

  puppet::environment { 'production':
    librarian => true,
  }

  puppet::environment { 'development':
    librarian    => false,
    branch       => 'master',
    mod_env      => 'development',
    cron_minutes => '10,25,40,55',
    user         => 'ubuntu',
    group        => 'ubuntu',
  }

  puppet::environment { 'testing':
    librarian    => false,
    cron_minutes => '5,35',
    branch       => 'master',
    mod_env      => 'development',
    user         => 'ubuntu',
    group        => 'ubuntu',
  }
*/
}
