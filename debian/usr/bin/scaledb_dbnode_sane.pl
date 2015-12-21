#!/usr/bin/perl

#
# $Id: scaledb_dbnode_sane.pl,v 1.1 2015-12-18 00:18:18 igor Exp $
#

use strict;
use warnings;
use POSIX ":sys_wait_h";
use POSIX qw(strftime);
use Getopt::Long;
use IO::Socket;
use Carp qw(croak cluck confess);

my $help;
my $mycnf;
my $verbose;
my $tool="scaledb_dbnode_sane.pl";
my $datadir="/var/lib/mysql";
my $scaledb_cnf;
my $mysql_err;
my $mycnf_param={};
my $dbnode_cnf={};
my $acquired={};
my $scaledb_debug_file;
my $error_exit_code;
my $ready_for_connection='';
my $scaledb_io_threads;
my $output_file;
my $meminfo={};
my @buffers = qw(
scaledb_buffer_size_index
scaledb_buffer_size_data
scaledb_buffer_size_blob
scaledb_global_hash_area_size
);

# 
# explain usage 
#
sub help {
	my $message = shift;
	my $status=0;
	if(defined $message){
		print "$message\n";
		$status=1;
	}
	print "USAGE: $tool -f mysql_config_file [ --verbose ]\n";
	exit $status;
}

#
# help messages, verbose mode
#
sub info {
	return if !$verbose or !@_;
	my $message = shift;
	my $ts = strftime("%Y-%m-%d %H:%M:%S",localtime);
	print "INFO: $ts - $message\n";
	if($output_file){
		print OUTF "INFO: $ts - $message\n";
	}
}

sub print_err {
	my $message='';
	if(!@_){
	}else{
		$message=shift;
	}
	my $ts = strftime("%Y-%m-%d %H:%M:%S",localtime);
	print "ERRO: $ts - $message\n";
	if($output_file){
		print OUTF "ERRO: $ts - $message\n";
	}
}

sub print_die {
	my $message='';
	if(!@_){
	}else{
		$message=shift;
	}
	my $ts = strftime("%Y-%m-%d %H:%M:%S",localtime);
	print "FATL: $ts - $message\n";
	if($output_file){
		print OUTF "FATL: $ts - $message\n";
		close OUTF;
		print "See Log:$output_file\n";
	}
	exit 1;
}



#
# send PING to ip:port - verify cas and slm life
# 
sub ping {
	my $sub    = "ping";
	my $status = 0;
	my $socket;
	if(@_!=2){
		print "$tool: ERROR - wrong ping arguments\n";
		exit 1;
	}
	my ($ip,$port)=@_;
	
	if(! ($socket = IO::Socket::INET->new(
			PeerAddr => $ip, 
			PeerPort => $port,
			Proto   => "tcp",
			Type            => SOCK_STREAM)))
	{
				return $status;
	}
	        
#	info "$sub - sending PING";
	print $socket "PING";
	my $answer=<$socket>;
#	info "$sub - received answer";
	if(!defined $answer){
#		info "$sub - answered undefined";
	}elsif($answer ne "PONG"){
#		info "$sub - bad answer:'$answer'";
	}else{ 
#		info "$sub - got answer:'$answer' - success";
		$status = 1;
	}
	close($socket);
#	info "$sub - exiting";
	return $status;
}

#
# read mysql configuration file
#
sub read_mycnf {
	my $sub = "read_mycnf";
	if(!-f $mycnf){
		print "$tool: ERROR - missing file:$mycnf\n";
		exit 1;
	}
	open MYCNF,"$mycnf" or print_die "failed to open $mycnf:$!";
	while(<MYCNF>){
		next if /^\s*#/;
		next if /^\s*$/;
		if(/^\s*(\S+)\s*=[ '"]*(.+)[ '"]*$/){
			my $param=$1;
			my $value=$2;
			$param=~s/-/_/g;
			info "$sub - got param:$param=$value";
			$mycnf_param->{$param}=$value;
		}
	}
	close MYCNF;
}

sub do_mycnf_params{
	my $sub = "do_mycnf_param";
	info "$sub - checking if datadir exists";
	if(exists $mycnf_param->{datadir}){
		$datadir=$mycnf_param->{datadir};
	}
	if(-d $datadir){
		info "$sub - datadir exists - ok";
	}else{
		print_die "$sub - failed to find mysql datadir:$datadir";
	}
	info "$sub - checking if scaledb db node config exists";
	$scaledb_cnf="$datadir/scaledb.cnf";
	if(exists $mycnf_param->{scaledb_config_file}){
		$scaledb_cnf=$mycnf_param->{scaledb_config_file};
	}
	if(-f $scaledb_cnf){
		info "$sub - scaledb dbnode config exists - ok";
	}else{
		print_die "$sub - failed to find scaledb dbnode config: $scaledb_cnf";
		exit 1;
	}
	info "$sub - checking if mysql error file exists";
	if(exists $mycnf_param->{log_error}){
		$mysql_err=$mycnf_param->{log_error};
	}else{
		print "$tool: ERROR - log-error not set, please configure \n";
	}
	if($mysql_err!~/\//){
		$mysql_err="$datadir/$mysql_err";
	}
	$mysql_err=~s/\.err//;
	$mysql_err="$mysql_err.err";
	if(-f $mysql_err){
		info "$sub - mysql error file exists - ok";
	}else{
		print_err "could not to find error file: $mysql_err\n";
	}
	close MYCNF; 
} 

sub do_scaledb_config {
	my $sub = "do_scaledb_config";
	open SDB_CNF,"$scaledb_cnf" or print_die "$sub - failed to open $scaledb_cnf:$!";
	while(<SDB_CNF>){
		next if /^\s*#/;
		next if /^\s*$/;
		if(/^\s*(\S+)\s*=[ '"]*(.+)[ '"]*$/){
			my $param=$1;
			my $value=$2;
			$param=~s/-/_/g;
			info "$sub - got param:$param=$value";
			$dbnode_cnf->{$param}=$value;
		}
	}
	close SDB_CNF;
}

sub do_mysql_err_file {
	my $sub = "do_mysql_err_file";
	open MYSQL_ERR_FILE,$mysql_err or print_die "$sub - failed to open $mysql_err:$!";
	while(<MYSQL_ERR_FILE>){
		chomp;
		# get ready for connection
		if(/ready for connections\./){
			$ready_for_connection=$_;
		}
		if(/^(scaledb|cas|slm)([-_a-z]+)\s*=[ '"]*(.+)[ '"]*$/){
			my $param="$1$2";
			my $value="$3";
			info "$sub - got acquired:$param=$value";
			$acquired->{"$1$2"}=$3;
		}
	}
	close MYSQL_ERR_FILE;
}

sub do_scaledb_debug_file {
	my $sub = "do_scaledb_debug_file";
	if(exists $dbnode_cnf->{scaledb_debug_file}){
		$scaledb_debug_file=$dbnode_cnf->{scaledb_debug_file};
	}
	if(! defined $scaledb_debug_file and exists $acquired->{scaledb_debug_file}){
		$scaledb_debug_file=$acquired->{scaledb_debug_file};
	}
	if(! defined $scaledb_debug_file ){
		print_die "$sub - failed to find scaledb_debug_file config param";
	}
	info "$sub - found scaledb_debug_file config: $scaledb_debug_file";
	$scaledb_debug_file="$scaledb_debug_file.00000";
	info "$sub - reading scaledb_debug_file: $scaledb_debug_file";
	
	open SDB_DEBUG_FILE,$scaledb_debug_file 
		or print_die "$sub - failed to open $scaledb_debug_file:$!";
	while(<SDB_DEBUG_FILE>){
		chomp;
		if($output_file){
			print OUTF "dbnode_debug_file: $_";
		}
		# get ready for connection
		if(/SDB Engine: error.*/){
			$error_exit_code=$_;
		}
	}
	close SDB_DEBUG_FILE;
}

sub do_cas_ping{
	my $sub = "do_cas_ping";
	my @cas_ips=();
	my @cas_ports=();
	my $cas_type='primary';
	my $param_id='server';
	if(@_){
		$cas_type=shift;
	}
	if($cas_type eq 'mirror'){
		$param_id="mirror";
	}elsif($cas_type eq 'primary'){
		$param_id="server";
	}else{
		print_die "$sub - wrong cas_type:$cas_type";
	}
	foreach my $cas_ips($acquired->{"scaledb_cas_".$param_id."_ips"}){
		#info "$sub - ips:$cas_ips";
		foreach my $ip(split /\s*,\s*/, $cas_ips){
			#info "$sub - ip:$ip";
			push @cas_ips,$ip;
		}
	}
	foreach my $cas_ports($acquired->{"scaledb_cas_".$param_id."_ports"}){
		#info "$sub - ports:$cas_ports";
		foreach my $port(split /\s*,\s*/, $cas_ports){
			#info "$sub - port:$port";
			push @cas_ports,$port;
		}
	}
	my $cas_index=0;
	foreach my $cas_ip(@cas_ips){
		my $cas_port=$cas_ports[$cas_index];
		print "testing cas $cas_type [$cas_index] ping $cas_ip:$cas_port  ";
		print  OUTF "testing cas $cas_type [$cas_index] ping $cas_ip:$cas_port" if $output_file;
		if(ping $cas_ip,$cas_port){
			print " .. Ok\n";
			print OUTF " .. Ok\n" if $output_file;
		}else{
			print " .. Nok\n";
			print OUTF " .. Nok\n" if $output_file;
		}
		$cas_index++;
	}
}
sub do_memory_check {
	my $sub = "do_memory_check";
	my $proc_meminfo = '/proc/meminfo';
	open MEM,$proc_meminfo or print_die "$sub - failed to open $proc_meminfo";
	while(<MEM>){
		if(/^([-_a-zA-Z]+):\s*(\d+)/){
			my ($mem_var,$mem_val)=($1,$2);
			info "$sub - got $mem_var=$mem_val";
			$meminfo->{$1}=$2;
		}
	}
	close MEM;
	my $mem_can=($meminfo->{Cached} + $meminfo->{MemFree})*1024;
	my $mem_total=$meminfo->{MemTotal}*1024;

	if($dbnode_cnf->{"scaledb_io_threads"}){
		$scaledb_io_threads=$dbnode_cnf->{"scaledb_io_threads"};
	}elsif($acquired->{"scaledb_io_threads"}){
		$scaledb_io_threads=$acquired->{"scaledb_io_threads"};
	}else{
		print_die "$sub - failed to find 'scaledb_io_threads'";
	}
	
	my $total_scaledb_memory=0;
	foreach my $buffer(@buffers){
		if($dbnode_cnf->{$buffer}){
			$total_scaledb_memory+=$dbnode_cnf->{$buffer};
		}elsif($acquired->{$buffer}){
			$total_scaledb_memory+=$acquired->{$buffer};
		}else{
			print_err "$sub - failed to find $buffer\n";
		}
	}
	my $buffer="scaledb_query_thread_analytics_area_size";
	if($dbnode_cnf->{$buffer}){
		$total_scaledb_memory=$dbnode_cnf->{$buffer}*$scaledb_io_threads;
	}elsif($acquired->{$buffer}){
		$total_scaledb_memory=$acquired->{$buffer}*$scaledb_io_threads;
	}else{
		print_err "$sub - failed to find $buffer\n";
	}
	info "$sub - total required memory:$total_scaledb_memory";
	info "$sub - total installed memory:$mem_total";
	info "$sub - total available memory:$mem_can";
}

sub open_output_file {
	my $sub = "open_output_file";
	return unless $output_file;
	if(-d $output_file){
		my $ts = strftime("%Y-%m-%d-%H%M-%S",localtime);
		$output_file="$output_file/sane.$ts.txt";
	}
	open OUTF,">$output_file" 
		or die "$tool: ERROR - failed to open output file:$!";
	info "$sub - output_file is directory";
	info "$sub - creating new file:$output_file";
}

# 
# MAIN
#
GetOptions("-f=s"=>\$mycnf,
			"-h=s"=>\$help,
			"verbose"=>\$verbose,
			"output-file=s"=>\$output_file);
help() if $help;
help("$tool: missing mysql configuration file") unless $mycnf;
open_output_file;
read_mycnf;
do_mycnf_params;
do_scaledb_config;
do_mysql_err_file;
do_scaledb_debug_file;
do_cas_ping('primary');
do_cas_ping('mirror');
do_memory_check;

if($output_file){
	my $ts = strftime("%Y-%m-%d %H:%M:%S",localtime);
	print OUTF "INFO: $ts - Finished\n";
	close OUTF;
	print "See Log:$output_file\n";
}
