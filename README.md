# bacula-fd-mon
The purpose of this project is to monitor and start Bacula jobs for clients who are not always online and whose schedules are unpredictable.

The Basic idea is, that the clients do not have schedules configured within Bacula Director, but only basic definitions. The bacula-fd-mon then monitors and starts the backup jobs as per the configuration.

The same thing can be accomplished within Bacula natively. However, it seemed to me to be less efficient, caused unneeded records in the database and a far more complicated configuration for such a simple task.
Concept

    Create backup and restore definitions (JobDefs?) for each client or client type (i.e. Windows or Linux). 

    These definitions are tied to a blank schedule. 

    The backup definition sets the expiration on the full backup via the "Max Full Interval" option in the JobDefs?. 

    The monitor always attempts an incremental and the server will determine if a full is needed when the current full backup has expired. 

    Via the monitor configuration, you set the schedule for how often the client should be backed up at a minimum. 

    The monitor will watch for the clients on the network and issue a backup as needed. 

Notes

    Each client will have to have a static IP. I used the static reservation configuration in my router to keep the client side network DHCP. 

    Must have expect installed. 

    The current code only supports SQLite3 database. 

    Must be co-located with the bacula server. 

Installation

tar -zxvf bacula-fd-mon-<VERSION>.tar.gz
cd bacula-fd-mon-<VERSION>
sudo ./install.sh

Example bacula-dir.conf

#############################
# Clients
#############################
Client {
   Name = ChrisPC
   Address = 192.168.75.120
   FDPort = 9102
   Catalog = Default
   Password = "password"
   File Retention = 8 days
   Job Retention = 8 days
   AutoPrune = yes
}

Client {
   Name = Malibu
   Address = 192.168.75.123
   FDPort = 9102
   Catalog = Default
   Password = "password"
   File Retention = 8 days
   Job Retention = 8 days
   AutoPrune = yes
}

#############################
# Job Defs
#############################
JobDefs {
   Name = "Backup Windows"
   Type = Backup
   FileSet = "Default Windows Client File Set"
   Schedule = "WeeklyCycle"
   Storage = bacs1
   Pool = Full
   Messages = Daemon
   Write Bootstrap = "/volumes/vg00-bacula/bootstraps/%n.bsr"
   Max Full Interval = 7 days
}

JobDefs {
   Name = "Backup Linux"
   Type = Backup
   FileSet = "Default Linux Client File Set"
   Schedule = "WeeklyCycle"
   Storage = bacs1
   Pool = Full
   Messages = Daemon
   Write Bootstrap = "/volumes/vg00-bacula/bootstraps/%n.bsr"
   Max Full Interval = 7 days
}

JobDefs {
   Name = "Restore Windows"
   Type = Restore
   FileSet = "Default Windows Client File Set"
   Storage = bacs1
   Pool = Full
   Messages = Daemon
   Where = /tmp/bacula-restore
}

JobDefs {
   Name = "Restore Linux"
   Type = Restore
   FileSet = "Default Linux Client File Set"
   Storage = bacs1
   Pool = Full
   Messages = Daemon
   Where = /tmp/bacula-restore
}

#############################
# Jobs
#############################
Job {
   Name = ChrisPC
   Client = ChrisPC
   JobDefs = "Backup Windows"
}

Job {
   Name = "Restore CPC"
   Client = ChrisPC
   JobDefs = "Restore Windows"

}

Job {
   Name = Malibu
   Client = Malibu
   JobDefs = "Backup Linux"
}

Job {
   Name = "Restore Malibu"
   Client = Malibu
   JobDefs = "Restore Linux"
}

#############################
# File Sets
#############################
FileSet {
  Name = "Default Windows Client File Set"

  Include {
    Options {
      signature = MD5
    }

    File = "C:/Users"
  }

  Exclude {
    File = "C:/Users/*/Temporary Internet Files/*"
    File = "C:/Users/*/Firefox/*/Cache/*"
    File = "C:/Users/*/Downloads/*.exe"
    File = "C:/Users/*/Downloads/*.msi"
  }
}

FileSet {
  Name = "Default Linux Client File Set"

  Include {
    Options {
      signature = MD5
    }

    File = /home
    File = /root
    File = /etc
    File = /usr/local
  }

  Exclude {
    File = "/*/.gvfs"
    File = "/home/*/.mozilla/firefox/*/Cache/*"
    File = "/home/*/Downloads/*"
  }
}

#############################
# Schedules
#############################
Schedule {
  Name = "WeeklyCycle"
}
