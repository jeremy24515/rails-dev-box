$ar_databases = ['activerecord_unittest', 'activerecord_unittest2']
$as_vagrant   = 'sudo -u vagrant -H bash -l -c'
$home         = '/home/vagrant'

# Pick a Ruby version modern enough, that works in the currently supported Rails
# versions, and for which RVM provides binaries.
$ruby_version = '2.0.0-p353'

Exec {
  path => ['/usr/sbin', '/usr/bin', '/sbin', '/bin']
}

# --- Preinstall Stage ---------------------------------------------------------

stage { 'preinstall':
  before => Stage['main']
}

class apt_get_update {
  exec { 'apt-get -y update':
    unless => "test -e ${home}/.rvm"
  }
}
class { 'apt_get_update':
  stage => preinstall
}

# --- SQLite -------------------------------------------------------------------

package { ['sqlite3', 'libsqlite3-dev']:
  ensure => installed;
}

# --- MySQL --------------------------------------------------------------------

class install_mysql {
  class { 'mysql': }

  class { 'mysql::server':
    config_hash => { 'root_password' => '' }
  }

  database { $ar_databases:
    ensure  => present,
    charset => 'utf8',
    require => Class['mysql::server']
  }

  database_user { 'rails@localhost':
    ensure  => present,
    require => Class['mysql::server']
  }

  database_grant { ['rails@localhost/activerecord_unittest', 'rails@localhost/activerecord_unittest2', 'rails@localhost/inexistent_activerecord_unittest']:
    privileges => ['all'],
    require    => Database_user['rails@localhost']
  }

  package { 'libmysqlclient15-dev':
    ensure => installed
  }
}
class { 'install_mysql': }

# --- PostgreSQL ---------------------------------------------------------------

class install_postgres {
  class { 'postgresql': }

  class { 'postgresql::server': }

  pg_database { $ar_databases:
    ensure   => present,
    encoding => 'UTF8',
    require  => Class['postgresql::server']
  }

  pg_user { 'rails':
    ensure  => present,
    require => Class['postgresql::server']
  }

  pg_user { 'vagrant':
    ensure    => present,
    superuser => true,
    require   => Class['postgresql::server']
  }

  package { 'libpq-dev':
    ensure => installed
  }

  package { 'postgresql-contrib':
    ensure  => installed,
    require => Class['postgresql::server'],
  }
}
class { 'install_postgres': }

# --- Memcached ----------------------------------------------------------------

class { 'memcached': }

# --- Packages -----------------------------------------------------------------

package { 'curl':
  ensure => installed
}

package { 'build-essential':
  ensure => installed
}

package { 'git-core':
  ensure => installed
}

# Nokogiri dependencies.
package { ['libxml2', 'libxml2-dev', 'libxslt1-dev']:
  ensure => installed
}

# --- Ruby ---------------------------------------------------------------------

exec { 'install_rvm':
  command => "${as_vagrant} 'curl -L https://get.rvm.io | bash -s stable'",
  creates => "${home}/.rvm/bin/rvm",
  require => Package['curl']
}

exec { 'install_ruby':
  # We run the rvm executable directly because the shell function assumes an
  # interactive environment, in particular to display messages or ask questions.
  # The rvm executable is more suitable for automated installs.
  #
  # use a ruby patch level known to have a binary
  command => "${as_vagrant} '${home}/.rvm/bin/rvm install ruby-${ruby_version} --binary --autolibs=enabled && rvm alias create default ${ruby_version}'",
  creates => "${home}/.rvm/bin/ruby",
  require => Exec['install_rvm']
}

# RVM installs a version of bundler, but for edge Rails we want the most recent one.
exec { "${as_vagrant} 'gem install bundler --no-rdoc --no-ri'":
  creates => "${home}/.rvm/bin/bundle",
  require => Exec['install_ruby']
}

# ---- PhantomJS ----------------------------------------------------------------
group { "puppet":
  ensure => "present"
}

# this is required by phantomjs
# https://github.com/ariya/phantomjs/issues/10904
package { "libfontconfig1":
  ensure => installed
}

# Setup phantomjs via netinstall
netinstall { "phantomjs":
  url => "http://phantomjs.googlecode.com/files/phantomjs-1.8.1-linux-i686.tar.bz2",
  extracted_dir => "phantomjs-1.8.1-linux-i686",
  destination_dir => "/tmp",
  postextract_command => "sudo cp /tmp/phantomjs-1.8.1-linux-i686/bin/phantomjs /usr/local/bin/"
}

# ---- JAVA ---------------------------------------------------------------------
class must-have {
  include apt
  apt::ppa { "ppa:webupd8team/java": }

  exec { 'apt-get update 2':
    command => '/usr/bin/apt-get update',
    require => [ Apt::Ppa["ppa:webupd8team/java"], Package["git-core"] ],
  }

  package { ["oracle-java7-installer"]:
    ensure => present,
    require => Exec["apt-get update 2"],
  }

  exec {
    "accept_license":
    command => "echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections && echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections",
    cwd => "/home/vagrant",
    user => "vagrant",
    path    => "/usr/bin/:/bin/",
    require => Package["curl"],
    before => Package["oracle-java7-installer"],
    logoutput => true,
  }
}
class { 'must-have':}

# ---- REDIS ---------------------------------------------------------------------
class redis {

  package { 'redis-server':
    ensure => installed
  }

  service { 'redis-server':
    ensure => "running",
    require => Package["redis-server"],
  }
}
class {'redis':}

# ---- NodeJS & NPM ------------------------------------------------------------
class nodejs {

  $nvm_version = "v0.17.0"

  $node_version = "v0.10.29"

  exec { 'install_nvm':
    command => "${as_vagrant} 'curl https://raw.githubusercontent.com/creationix/nvm/${nvm_version}/install.sh | bash'",
    creates => "/home/vagrant/.nvm",
    require => Package['curl'],
    logoutput => true,
  }
 
  exec { 'install_nodejs':
    command => "${as_vagrant} 'source /home/vagrant/.nvm/nvm.sh && nvm install ${node_version} && nvm alias default ${node_version}'",
    creates => "/home/vagrant/.nvm/${node_version}",
    require => Exec['install_nvm'],
    logoutput => true,
  }

  # change registry en http, sinon erreur
  exec { "npm-change-reg":
    command => "${as_vagrant} '/home/vagrant/.nvm/${node_version}/bin/npm config set registry http://registry.npmjs.org/'",
    require => Exec["install_nodejs"],
    unless => "/home/vagrant/.nvm/${node_version}/bin/npm config get registry | grep http://registry.npmjs.org/",
    logoutput => true,
  }

}
class {'nodejs':}

# --- Locale -------------------------------------------------------------------

# Needed for docs generation.
exec { 'update-locale':
  command => 'update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8'
}
