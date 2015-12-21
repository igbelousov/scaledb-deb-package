#!/usr/bin/env perl

#
# $Id: scaledb_cas_diag.pl,v 1.1 2015-12-18 00:18:18 igor Exp $
#

#
# to analyze CAS configuration with respect to file system layout,
#  network and memory
#

use strict;
use warnings;
use Getopt::Long;
use File::Basename;

my $ERRORS =0;
my %config =();
my $cas_cnf=undef;
my $shard  =1;
my $mirror =undef;
my $verbose=undef;
my $help   =undef;

my $ts = time;
my $temp_dir=defined $ENV{TEMP}?$ENV{TEMP}:"/tmp";
my $output_file = "$temp_dir/$ENV{USER}.cas_info.$ts.txt";

sub help {
    print "Usage: --config=<cas_cnf> [options]\n";
    print "       options:\n";
    print "               --shard=N    : shard id for this CAS (default :1)\n";
    print "               --mirror     : set for mirror (default :false)\n";
    print "               --help       : prints this message and exit\n";
    print "               --verbose    : prints messages about what it does\n";
    print "               -o filename  : stores diagnostics into file (default : \$TEMP/\$USER.cas_info.txt\n";
    exit 1;
}

sub info {
    my $message = shift;
    my ($Y,$M,$D,$h,$m,$s) = (localtime())[5,4,3,2,1,0];
    $Y+=1900;
    $M+=1;
    my $formated_message=sprintf("%d-%02d-%02d %02d:%02d.%02d INFO %s\n",$Y,$M,$D,$h,$m,$s,$message);

    # always print to output file for diagnostics
    print FINFO $formated_message;

    # but only print to STDOUT when user set $verbose flag
    return unless $verbose ;
    print $formated_message;
}

sub info2 {
    my $message = shift;
    my ($Y,$M,$D,$h,$m,$s) = (localtime())[5,4,3,2,1,0];
    $Y+=1900;
    $M+=1;
    my $formated_message=sprintf("%d-%02d-%02d %02d:%02d.%02d INFO %s\n",$Y,$M,$D,$h,$m,$s,$message);
    print FINFO $formated_message;
}

sub error_exit {
    my $message = shift;
    my ($Y,$M,$D,$h,$m,$s) = (localtime())[5,4,3,2,1,0];
    $Y+=1900;
    $M+=1;
    my $formated_message = sprintf("%d-%02d-%02d %02d:%02d.%02d FATAL %s\n",$Y,$M,$D,$h,$m,$s,$message);
    $ERRORS=1 if($ERRORS==0);
    print FINFO $formated_message;
    print $formated_message;

    print FINFO "Total errors: $ERRORS\n";
    print "Total errors: $ERRORS\n";

    close FINFO;

    print "Results of this run saved in '$output_file'\n";
    exit 1;
}

sub error {
    $ERRORS++;
    my $message = shift;
    my ($Y,$M,$D,$h,$m,$s) = (localtime())[5,4,3,2,1,0];
    $Y+=1900;
    $M+=1;
    my $formated_message = sprintf("%d-%02d-%02d %02d:%02d.%02d ERROR %s\n",$Y,$M,$D,$h,$m,$s,$message);
    print FINFO $formated_message;
    print $formated_message;
}

sub testdir {
    my $sub = "testdir";
    info2 "$sub - entered";

    my $dbname = shift;
    my $dbdir  = shift;

    if(!defined $dbdir){
        error "$sub - parameter '$dbname' does not have directory assigned";
        return;
    }

    info2 "$sub - validating '$dbdir' for '$dbname'";
    error "$sub - parameter '$dbname' has directory '$dbdir' that does not exists"   unless -d $dbdir;
    error "$sub - parameter '$dbname' has directory '$dbdir' that is not readable"   unless -r $dbdir;
    error "$sub - parameter '$dbname' has directory '$dbdir' that is not exectuable" unless -x $dbdir;

    info2 "$sub - exited";
}

sub check_must_haves{
    my $sub = "check_must_haves";
    info2 "$sub - entered";
    my @must_haves = qw(scaledb_cas_server_ips scaledb_cas_server_ports scaledb_data_directory scaledb_log_directory scaledb_buffer_size_data scaledb_buffer_size_index  scaledb_cas_service_port);
    foreach my $param(@must_haves){
            info "$sub - verifying config param '$param' exists";
            if(!exists $config{$param}){
                error "$sub - missing config parameter:'$param'";
                info2 "$sub - dumping configs:";
                map{info2 "    '$_'='$config{$_}'\n"} (keys %config);
                error_exit "$sub - can't continue without '$param'";
            }
    }

    info2 "$sub - exited";
}

#
# returns true if param is know
# false otherwise
#
sub check_known_params{
    my $sub = "check_known_params";
    my $new_param = shift;
    info2 "$sub - received param '$new_param'";
    my %list_of_params = (
    "scaledb_data_directory"=>1,
    "scaledb_cas_service_port"=>1,
    "scaledb_log_directory"=>1,
    "scaledb_max_file_handles"=>1,
    "scaledb_aio_flag"=>1,
    "scaledb_hash_lookup_size"=>1,
    "scaledb_io_threads"=>1,
    "scaledb_cas_server_ips"=>1,
    "scaledb_cas_server_ports"=>1,
    "scaledb_cas_mirror_ips"=>1,
    "scaledb_cas_mirror_ports"=>1,
    "scaledb_cas_multicast_ips"=>1,
    "scaledb_cas_multicast_ports"=>1,
    "scaledb_slm_threads"=>1,
    "scaledb_buffer_size_index"=>1,
    "scaledb_buffer_size_data"=>1,
    "scaledb_buffer_size_blob"=>1,
    "scaledb_dead_lock_milliseconds"=>1,
    "scaledb_max_column_length_in_base_file"=>1,
    "scaledb_cluster_user"=>1,
    "scaledb_cluster_password"=>1,
    "scaledb_debug"=>1,
    "scaledb_debug_interactive"=>1,
    "scaledb_debug_buffer_size"=>1,
    "scaledb_debug_file"=>1,
    "scaledb_debug_lines_per_file"=>1,
    "scaledb_debug_files_count"=>1,
    "scaledb_debug_string"=>1,
    "scaledb_debug_locking_mode"=>1,
    "slm_debug"=>1,
    "slm_debug_interactive"=>1,
    "slm_debug_lines_per_file"=>1,
    "slm_debug_files_count"=>1,
    "scaledb_log_sql"=>1,
    "scaledb_max_file_size"=>1,
    "scaledb_disable_optimization"=>1,
    "scaledb_log_io_flags"=>1,
    "scaledb_cluster_port"=>1,
    "cas_recovery_mode"=>1,
    "scaledb_enable_lock_tests"=>1,
    "scaledb_data_io_flags"=>1,
    "scaledb_enable_optimization"=>1,
    "scaledb_global_hash_area_size"=>1,
    "scaledb_max_analytics_area_size"=>1,
    "scaledb_autocommit"=>1,
    "scaledb_index_threads"=>1,
    "scaledb_var_char_percentage"=>1,
    );

    #
    # scaledb_db_directory is different type of param
    # process it differently 
    #
    if($new_param=~/^scaledb_db_directory\s+(.*)$/){
        my $dbname=$1;
        if($dbname!~/^[a-zA-Z0-9_]+/){
            error "$sub - scaledb_db_directory set with bad database name '$dbname'";
            return 0;
        }
        info "$sub - verified '$new_param' - ok";
        return 1;
    }

    if(!exists $list_of_params{$new_param}){
     error "$sub - parameter:'$new_param' is unknown" ;
     return 0;
    }
     
    info "$sub - verified '$new_param' - ok";
    info2 "$sub - exited";
    return 1;
}

#
# From Mb to Kb
#
sub calc_scaledb_memory {
    my $sub = "calc_scaledb_memory";
    info2 "$sub - entered";

    #
    #  when blob size is not specified
    #  default is 50M 
    #
   if(! exists $config{scaledb_buffer_size_blob} ) {
        info2 "$sub - scaledb_buffer_size_blob is not set by user, assume default 50M"; 
        $config{scaledb_buffer_size_blob}="50M";
   }

    #
    #  when buffers specified in 8Kblocks
    #
   foreach my $component ( qw(index data blob)){
       info2 "$sub - cache configuration for $component: ".
             $config{"scaledb_buffer_size_$component"};

       if($config{"scaledb_buffer_size_$component"}=~/^(\d+)$/){
            info2 "$sub - cache for '$component' configured in 8K blocks!";
            $config{"scaledb_buffer_size_$component"}=$1*8;
        } 
    }

    #
    # when buffers specified in Mb
    #
   foreach my $component ( qw(index data blob)){
       if($config{"scaledb_buffer_size_$component"}=~/^(\d+)\s*M$/){
            $config{"scaledb_buffer_size_$component"}=$1*1024;
        } 

        if($config{"scaledb_buffer_size_$component"}!~/^(\d+)$/){
            error "$sub - invalid value '$1' for $component cache configuration";
            next;
        }

        info "$sub - converted cache size for $component to (Kb) ".
             $config{"scaledb_buffer_size_$component"};
    }

    info2 "$sub - exited";
}

#
#
# MAIN
#
#
GetOptions("config=s"=>\$cas_cnf,
        "shard=n"=>\$shard,
        "mirror"=>\$mirror,
        "help"=>\$help,
        "verbose"=>\$verbose,
        "o=s"=>\$output_file);

help() unless $cas_cnf;
help() if $help;

open FINFO,">$output_file" 
    or die "Failed openning output file for diagnostic messages:$output_file:$!\n";

info2 "main - dumping diagnositcs to '$output_file'";

if ( ! -r $cas_cnf ){
    error_exit "main - $cas_cnf does not exist or is not readable"; 
}


open FCNF,"$cas_cnf"
    or error_exit "main - failed to open configuration $cas_cnf:$!\n";

info "main - reading configuration from '$cas_cnf'";

while(<FCNF>){
    next if /^#/;
    chomp;
    if(/\s*(.*?)\s*=\s*(.*?)\s*$/){
        my $param=$1;
        my $value=$2;
        info2 "main - got cas config param :'$param'='$value'";
        next unless check_known_params($param);
        $value=~s/("|')//g;
        if(exists $config{$param}){
            error "main - param '$param' reassigning from '$config{$param}' to '$config{$param}'";
        }
        $config{$param}=$value;
    }
}
close FCNF;

check_must_haves();

#
# directory testing
#
testdir('scaledb_data_directory',$config{scaledb_data_directory});
testdir('scaledb_log_directory',$config{scaledb_log_directory});

#
# test db directory
#
foreach my $param (keys %config){
   next unless $param=~/^scaledb_db_directory\s*(.*)$/;
   my $dbname=$1;
   my $dbdir=$config{$param};
   testdir($dbname,$dbdir);
}

#
# directory for debug file
#
if (exists $config{scaledb_debug_file}){
   testdir('scaledb_debug_file',dirname($config{scaledb_debug_file}));
}

#
# how many shards?
#
my @cas_ips;
my @cas_ports;
if (!$mirror){
  info "main - extracting specified CAS ip and port information for shard:$shard";
  @cas_ips   = split /,/,$config{scaledb_cas_server_ips};
  @cas_ports = split /,/,$config{scaledb_cas_server_ports};
}else{
  info "main - extracting specified CAS mirror ip and port information for shard:$shard";
  @cas_ips   = split /,/,$config{scaledb_cas_mirror_ips};
  @cas_ports = split /,/,$config{scaledb_cas_mirror_ports};
}

info "main - CAS configured for ".scalar @cas_ips." shards";
if(@cas_ips<$shard){
   error_exit "main - requested ip address for non-existing shard# $shard\n";

}
if(@cas_ports<$shard){
   error_exit "requested ip port for non-existing shard# $shard\n";
}

my $cas_ip   = $cas_ips[$shard-1];
my $cas_port = $cas_ports[$shard-1];
$cas_ip=~s/\s*//g;
$cas_port=~s/\s*//g;

#
# bad formating 
# 
error_exit "main - bad ip address:$cas_ip" if $cas_ip!~/^\d+\.\d+\.\d+\.\d+$/;
error_exit "main - bad port :$cas_port"    if $cas_port!~/^\d+$/;
info "main - verifying availability of address '$cas_ip:$cas_port'";

#
# TESTING THAT IP ADDRESS AVAILABLE
#
info2 "main - searching for ifconfig binary";
my $ifconfig=`which ifconfig 2>/dev/null`;
if (!defined $ifconfig){
    info2 "didn't find ifconfig in PATH, looking in other places";
  foreach my $dir (qw(/sbin /usr/sbin /usr/local/sbin)){
     $ifconfig="$dir/ifconfig" if -f "$dir/ifconfig";
  }
}
error_exit "failed to find ifconfig, can't continue" unless $ifconfig;
chomp $ifconfig;
info "main - found ifconfig: '$ifconfig'";

my @ifcfg_output=`$ifconfig 2>&1`;
error_exit "failed to exec ifconfig:@ifcfg_output" if($?);

info2 "main - collecting ip addresses from ifconfig output";
my %ipaddr=();
foreach my $ifcfg_line (@ifcfg_output){
   if ($ifcfg_line=~/inet addr:(\d+\.\d+\.\d+\.\d+)\s+/){
        info2 "main - found ip:$1";
        $ipaddr{$1}=1;
   }
}
error "main - CAS shard $shard configured for $cas_ip, ".
      "but there is no such addresses available" 
       unless exists $ipaddr{$cas_ip};

#
# CAS_PORT should be in allowable range and available
#
error "main - cas_port:$cas_port is not in ".
      "permissisble range:(1000 to 56000)" 
      if $cas_port<1000 or $cas_port>56000;

#
# network testing
#
my @listeners=();
info "main - searching for netstat binary in PATH";
my $netstat = `which netstat 2>/dev/null`;
error_exit "main - failed to find netstat" if($?);
chomp $netstat;

$netstat = "$netstat -t -n -p -l -T ";
info "main - runnning '$netstat' to determine running TCP servers";

my @ntout = `$netstat 2>&1`;
error "main - failed to run netstat:@ntout" if ($?);

foreach my $line (@ntout){
    next unless $line=~/^tcp/;
    my $server = (split/\s+/,$line)[3];

    my ($server_ip,$server_port) = split/:/,$server;
    if($server_ip eq '0.0.0.0' and $server_port==$cas_port){
        error "main - port $cas_port is not available - it is already in use";
    }

    if($server_ip eq $cas_ip and $server_port==$cas_port){
        error "main - address $cas_ip:$cas_port is not available - it is already in use";
    }
}

#
# got overal scaledb 
#
calc_scaledb_memory ();

#
# Memory - better look into /proc/meminfo
#
# MemTotal
# MemFree
# Cached
# 
# only linux
#
info "main - verifying memory configuration";
my %meminfo = ();
my $mem_total=0;
my $mem_free=0;
my $mem_cached=0;
open MEMINFO,"/proc/meminfo"
    or error_exit "main - failed to open /proc/meminfo:$!";
while(<MEMINFO>){
    chomp;
    if (/^(\w+):\s*(\d+)\b/){
        info2 "main - meminfo:'$1'='$2'";
        $meminfo{$1}=$2; 
    }
}
close MEMINFO;

my $available_memory = $meminfo{MemFree}+$meminfo{Cached};
my $cas_requested_memory = $config{scaledb_buffer_size_index} +
                        $config{scaledb_buffer_size_data} +
                        $config{scaledb_buffer_size_blob};

info "main - comparing available_memory(KB):'$available_memory' to needed '$cas_requested_memory'";

my $diff = 100*$cas_requested_memory/$available_memory;
info2 "main - calculated prcntl diff: $diff ";

if ($cas_requested_memory>$available_memory){
    error "main - requested too much memory for cas!";
}elsif ($diff > 80 ){ 

    error "main - CAS maybe configured for too much memory !"; 
}else{
    info "main - memory allocation for cas looks ok";
}

#
# our information collected
#
close FINFO;
print "Results of this run saved in '$output_file'\n";

#
#my $vmstat;
#if($^O eq 'darwin'){
#   $vmstat=`which vm_stat 2>/dev/null`;
#}else{
#   $vmstat=`which vmstat 2>/dev/null`;
#}
#
