#!/usr/bin/perl
##################################################################################
# Copyright (C) 2011  Chris Rutledge <rutledge.chris@gmail.com>
#
# http://code.google.com/p/bacula-fd-mon/
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
##################################################################################
use Getopt::Long;
use DBI;
use IO::Socket;
use POSIX;

my $CFILE  = "/etc/bacula/bacula-fd-mon.cfg";
my $HELP   = undef;
my $DEBUG  = undef;
my $DRYRUN = undef;
my $DAEMON = undef;
my $LOG    = undef;
my $dbh    = undef;

GetOptions ("help|h"     => \$HELP,
            "config|c=s" => \$CFILE,
            "debug|d"    => \$DEBUG,
            "dryrun"     => \$DRYRUN,
            "daemon"     => \$DAEMON,
            "log|l=s"    => \$LOG);

if ($HELP) {
   printHelp();

   unlockThenExit(1);
}

my $CONFIG = loadConfig();

validateConfig();

if ( -f "$CONFIG->{'LOCKF'}" ) {
   print "Lock file exists: $CONFIG->{'LOCKF'}\n";
   print "If process is not running, please remove this file\n";
   print "Exiting\n";

   exit(1);
}

lockFile();

if ($DAEMON) {
   $DPID = fork();

   if ( $DPID < 0 ) {
      die("fork: $!\n");
   } elsif ( $DPID ) {
      exit(0);
   }

   chdir('/tmp');

   umask('0');

   foreach ( 0 .. (POSIX::sysconf (&POSIX::_SC_OPEN_MAX) || 1024) ) {
      POSIX::close($_);
   }

   open(STDIN,  "</dev/null") or die("Can't open: /dev/null\n");
   open(STDOUT, ">>$LOG") or die("Can't open: $LOG\n");
   open(STDERR, ">>$LOG") or die("Can't open: $LOG\n");

   if ($DEBUG) {
      printFormating("In daemon mode");
   }

   my $run = 1;

   $SIG{TERM}   = sub { printFormating("Received TERM signal, terminating"); $run = undef; };
   # This is broken and commented out for now.
   #$SIG{SIGHUP} = sub { printFormating("Received SIGHUP, reloading configuration"); $CONFIG = loadConfig(); };

   while($run) {
      $dbh = dbConnect();

      scanClients();

      $dbh->disconnect();

      sleep($CONFIG->{'SINTERVAL'});
   }
} else {
   if ($DEBUG) {
      printFormating("In standard mode");
   }

   $dbh = dbConnect();

   scanClients();

   $dbh->disconnect();
}

$dbh->disconnect();

unlockThenExit(0);


#############################################
# Subs
#############################################
sub printFormating {
   my $line = $_[0];

   my $date = `date`;

   chomp($date);

   print "$date: $line\n";
}
sub dbConnect {
   return(DBI->connect("dbi:$CONFIG->{'DBTYPE'}:dbname=$CONFIG->{'DB'}","$CONFIG->{'DBUSER'}", "$CONFIG->{'DBPASS'}", { RaiseError => 1, AutoCommit => 0 }));
}

sub printHelp {
   print "Usage: $0 [options]\n\n";
   print "Options:\n";
   print "   --help|-h:                   print this message.\n";
   print "   --config|-c <CONFIGFILE>:    configuration file. Default is $CFILE\n";
   print "   --debug|-d:                  turn debugging on.\n";
   print "   --dryrun:                    assumes client needs a backup but does NOT actually run the backup job.\n";
   print "   --daemon:                    runs as a daemon.\n";
   print "   --log|-l <LOGFILE>:          specifies the log file, Default is /var/log/bacula-fd-mon.log\n";
}

sub loadConfig {
   if ($DEBUG) {
      printFormating("READ CONFIG START");
   }

   if ( ! -f $CFILE ) {
      printFormating("ERR: Could not load file: $CFILE");

      unlockThenExit(2);
   }

   open(CFH, "$CFILE") or die("Can't open: $CFILE\n");

   while(<CFH>) {
      $_ =~ s/\s+//g;

      chomp($_);

      if ($_ =~ /^#/ || $_ =~ /^\s+#/ || $_ =~ /^$/ || $_ =~ /^\s+$/ || $_ =~ /[\[|\]]/) {
         if ($DEBUG) {
            printFormating("SKIPPING: $_");
         }

         next;
      }

      if ($_ =~ /=/) {
         if ($DEBUG) {
            printFormating("INCLUDING (=): $_");
         }

         my ($key, $value) = split("=", $_);

         if ($DEBUG) {
            printFormating("  KEY   = $key");
            printFormating("  VALUE = $value");
         }

         $C{uc($key)} = $value;
      }

      if ($_ =~ /:/) {
         if ($DEBUG) {
            printFormating("INCLUDING (:): $_");
         }

         push(@{$C{'JOBS'}}, $_);
      }
   }

   close(CFH);

   if ($DEBUG) {
      printFormating("READ CONFIG END");
   }

   return(\%C);
}

sub validateConfig {
   if (! $CONFIG->{'DBTYPE'}) {
      printFormating("validateConfig: DBTYPE not set");

      unlockThenExit(2);
   }

   if (! $CONFIG->{'DB'}) {
      printFormating("validateConfig: DB not set");

      unlockThenExit(3);
   }

   if (! $CONFIG->{'LOCKF'}) {
      printFormating("validateConfig: LOCKF not set");

      unlockThenExit(4);
   }

   if (@{$CONFIG->{'JOBS'}} == 0) {
      printFormating("validateConfig: No enabled job configurations");

      unlockThenExit(5);
   }

   if (! $CONFIG->{'CTIMEOUT'} || $CONFIG->{'CTIMEOUT'} !~ /[0-9]*/) {
      $CONFIG->{'CTIMEOUT'} = 2;
   }

   if (! $CONFIG->{'SINTERVAL'} || $CONFIG->{'SINTERVAL'} !~ /[0-9]*/) {
      $CONFIG->{'SINTERVAL'} = 120;
   }

   if (! -f "$LOG") {
      $LOG = "/var/log/bacula-fd-mon.log";
   }
}

sub scanClients {
   for (@{$CONFIG->{'JOBS'}}) {
      my $port     = getPort($_);
      my $IP       = getIP($_);
      my $jobname  = getJobName($_);
      my $interval = getInterval($_);

      printFormating("PROCESSING JOB: Details: Port: $port - IP: $IP - JobName: $jobname - Interval: $interval");
   
      ##################
      # Check if a backup is needed
      ##################
      if (isBackupNeeded($jobname, $interval)) {
         printFormating("Backup IS needed");
   
         ##################
         # Check if a backup is currently running
         ##################
         if (isJobRunning($jobname)) {
            printFormating("Has one or more running jobs");
      
            next;
         } else {
            printFormating("Has NO running jobs");
   
            ##################
            # Check to see if client fd is running
            ##################
            if (isClientRunning($port, $IP)) {
               printFormating("File daemon is running");
   
               runBackup($jobname);
            } else {
               printFormating("File daemon is NOT running");
      
               next;
            }
         }
      } else {
         printFormating("Backup IS NOT needed");
   
         next;
      }
   }
}

sub getPort {
   my $line = $_[0];

   my (@parts) = split(/:/, $line);

   chomp($parts[2]);

   if ($parts[2]) {
      return($parts[2]);
   } else {
      return("9102");
   }
}

sub getIP {
   my $line = $_[0];

   my (@parts) = split(/:/, $line);

   chomp($parts[0]);

   return($parts[0]);
}

sub getJobName {
   my $line = $_[0];

   my (@parts) = split(/:/, $line);

   chomp($parts[1]);

   return($parts[1]);
}

sub getInterval {
   my $line = $_[0];

   my (@parts) = split(/:/, $line);

   chomp($parts[3]);

   if ($parts[3]) {
      return($parts[3]);
   } else {
      return("-1 day");
   }
}

sub isClientRunning {
   my ($port, $IP) = @_;

   my $socket = IO::Socket::INET->new(PeerAddr => $IP, PeerPort => $port, Proto => 'tcp', Timeout => $CONFIG->{'CTIMEOUT'});

   my $socket_status = undef;

   if ($socket) {
      $socket_status = 1;

      $socket->close();
   }

   return($socket_status);
}

sub isJobRunning {
   my ($jobname) = $_[0];

   my $sth = $dbh->prepare("SELECT count(*) AS count FROM job WHERE name = ? and jobstatus IN ('C', 'R', 'B', 'D', 'F', 'S', 'm', 'M', 's', 'j', 'c', 'd', 't', 'p', 'a', 'i')");
 
   $sth->bind_param(1, $jobname);

   $sth->execute();

   my $rowCount = $sth->fetchrow_hashref();

   $sth->finish();

   if ($$rowCount{'count'} > 0) {
      return(1);
   } else {
      return(undef);
   }
}

sub isBackupNeeded {
   my ($jobname) = $_[0];
   my ($interval) = $_[1];

   my $sth = undef;

   if ($CONFIG->{'DBTYPE'} == "SQLite") {
      # specification for $interval is already SQLite specific.
      $sth = $dbh->prepare("SELECT COUNT(*) AS count FROM job WHERE name = ? and jobstatus IN ('T', 'E', 'e') AND endtime > DATETIME('now', ?)");

      $sth->bind_param(2, $interval);
   } elsif ($CONFIG->{'DBTYPE'} == "mysql") {
      # need to make $interval and the query specific to mysql
   } elsif ($CONFIG->{'DBTYPE'} == "oracle") {
      # need to make $interval and the query specific to oracle
   } else {
      print "Database type $CONFIG->{'DBTYPE'} is currently no implemented\n";
      return(undef);
   }
 
   $sth->bind_param(1, $jobname);

   $sth->execute();

   my $rowCount = $sth->fetchrow_hashref();

   $sth->finish();

   if ($DRYRUN) {
      return(1);
   }

   if ($$rowCount{'count'} == 0) {
      return(1);
   } else {
      return(undef);
   }
}

sub runBackup {
   $jobname = $_[0];

   $runjob = getRunJob();
   $bcon   = getBCon();

   printFormating("Executing: $runjob $bcon $jobname");

   printFormating("+++++++++++++++++++++++++++++");

   if ($DRYRUN) {
      printFormating("DRYRUN enabled, will not execute");
   } else {
      system("$runjob", "$bcon", "$jobname");
   }

   printFormating("+++++++++++++++++++++++++++++");
}

sub getRunJob {
   if (-x $CONFIG->{'RUNJOB'}) {
      return($CONFIG->{'RUNJOB'});
   } else {
      if (-x "/usr/bin/bacula_runjob.exp") {
         return("/usr/bin/bacula_runjob.exp");
      } else {
         printFormating("Unable to locate bacula_runjob.exp!");

         unlockThenExit(6);
      }
   }
}

sub getBCon {
   if (-x $CONFIG->{'BCON'}) {
      return($CONFIG->{'BCON'});
   } else {
      my $bcon = "/usr/sbin/bconsole";

      if (-x $bcon) {
         return($bcon);
      } else {
         printFormating("Unable to locate bconsole!");
   
         unlockThenExit(6);
      }
   }
}

sub lockFile {
   system("touch", "$CONFIG->{'LOCKF'}");
}

sub unlockFile {
   if ( -f "$CONFIG->{'LOCKF'}") {
      system("rm", "$CONFIG->{'LOCKF'}");
   }
}

sub unlockThenExit {
   printFormating("Removing lock file");

   unlockFile();

   printFormating("Exiting with code: $_[0]");

   exit($_[0]);
}
