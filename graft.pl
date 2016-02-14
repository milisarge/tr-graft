#!xPERLx -w

#
# Virtual package installer.
#
# Author: Peter Samuel <peter.r.samuel@gmail.com>

###########################################################################
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA, or download it
# from the Free Software Foundation's web site:
#
#	http://www.gnu.org/copyleft/gpl.html
#	http://www.gnu.org/copyleft/gpl.txt
#

###########################################################################
#
# System defaults

use strict;
use File::Basename;
use Getopt::Long qw (:config bundling no_ignore_case);

$| = 1;

my %config;				# Configuration and other runtime values
my %option;				# Command line options

init();					# Argument parsing and set up

###########################################################################
#
# Process each package provided on the command line

foreach my $package (@ARGV)
{
    $package = stripslashes($package);

    # Complain if the package directory is empty

    if ($package eq '')
    {
	message(
		tag	=> 'ERROR',
		msg	=> 'Package directory cannot be empty.',
	    );

	$config{errorStatus} = 3;
	next;
    }

    # If the package is not fully qualified, prepend it with the
    # default package target.

    unless (fullyqualified($package))
    {
	$package = $config{packageDefault} . '/' . $package;
    }

    # Complain if the package directory does not exist.

    unless (-d $package)
    {
	message(
		tag	=> 'ERROR',
		msg	=> "Package directory $package does not exist.",
	    );

	$config{errorStatus} = 3;
	next;
    }

    if (exists $option{s})
    {
	# Stow/Depot compatibility mode. Stow and Depot (in their
	# default modes) assume that packages are installed in
	# /dir/stow/pkg-nn or /dir/depot/pkg-nn. They also assume the
	# symbolic links will be created in /dir. Graft's Stow/Depot
	# compatibility mode takes a single argument as the
	# installation directory of the package and grafts it into the
	# directory which is the dirname of the dirname of the
	# argument. (That's not a typo! That really _is_ two lots of
	# dirname operations).

	$config{target} = dirname dirname $package;
    }

    if (exists $option{i})
    {
	message(
		tag	=> 'Installing',
		msg	=> "links to $package in $config{target}"
	    ) if $config{verbose};

	logger(
		tag	=> 'I',
		log	=> [ $package, $config{target} ],
	    ) unless (exists $option{n});

	install(
		source	=> $package,
		target	=> $config{target},
	    );

	next;
    }

    if (exists $option{d})
    {
	message(
		tag	=> 'Uninstalling',
		msg	=> "links from $config{target} to $package",
	    ) if $config{verbose};

	logger(
		tag	=> 'D',
		log	=> [ $package, $config{target} ],
	    ) unless (exists $option{n});

	uninstall(
		source	=> $package,
		target	=> $config{target},
	    );

	next;
    }

    if (exists $option{p})
    {
	message(
		tag	=> 'Pruning',
		msg	=> "files in $config{target} which conflict with $package",
	    ) if $config{verbose};

	# Pruning is a special case of deletion

	logger(
		tag	=> 'P',
		log	=> [ $package, $config{target} ],
	    ) unless (exists $option{n});

	uninstall(
		source	=> $package,
		target	=> $config{target},
	    );

	next;
    }
}

exit $config{errorStatus};

###########################################################################

sub cat
{
    # Open the named file and return a hash of the lines in the file.
    # Duplicate entries are handled automatically by the hash.

    my $file = shift;
    my %hash;

    if (defined open FILE, $file)
    {
	while (<FILE>)
	{
	    chomp;
	    ++$hash{$_};
	}

	close FILE;
	return %hash;
    }
    else
    {
	message(
		tag	=> 'ERROR',
		msg	=> "Could not open $file for reading: $!."
	    );

	return undef;
    }
}

sub directories
{
    # Return a hash of directories beneath the current directory.
    # The special directories '.' and '..' will not be returned.
    # Symbolic links to directories will be treated as links and
    # NOT as directories.

    my $cwd = shift;
    my %dirs;

    if (opendir DOT, '.')
    {
	foreach (readdir DOT)
	{
	    next if /^\.\.?$/;		# ignore '.' and '..'
	    next unless -d;		# ignore non directories
	    next if -l;			# ignore symbolic links to directories
	    ++$dirs{$_};
	}

	closedir DOT;
	return %dirs;
    }
    else
    {
	message(
		tag	=> 'ERROR',
		msg	=> "Could not open directory $cwd for reading: $!"
	    );

	return undef;
    }
}

sub files
{
    # Return a hash of non directories beneath the current directory.
    # Symbolic links to directories will also be returned.

    my $cwd = shift;
    my %files;

    if (opendir DOT, '.')
    {
	foreach (readdir DOT)
	{
	    next if (-d and not -l);	# ignore real directories,
	    				# symlinks to directories are OK.
	    ++$files{$_};
	}

	closedir DOT;
	return %files;
    }
    else
    {
	message(
		tag	=> 'ERROR',
		msg	=> "Could not open directory $cwd for reading: $!",
	    );

	return undef;
    }
}

sub fullyqualified
{
    # return true if the argument is a fully qualified directory name

    my $string = shift;

    return $string =~ /^\// ? 1 : 0;
}

sub init
{
    # Die now if the OS does not support symbolic links!

    (eval 'symlink "", "";', $@ eq '')
	or die "Your operating system does not support symbolic links.\n";

    ###########################################################################
    #
    # System defaults

    # Get the RCS revision number. If the file has been checked out for
    # editing, add '+' to the revision number to indicate its state. The
    # revision number is written to the log file for every graft operation.
    # This is only used for testing new development versions.

    my @rcsid = split(' ',
	'$Id: graft.pl,v 2.8 2015/11/23 22:25:58 psamuel Exp $');

    $config{version} = $rcsid[2];
    $config{version} .= '+' if (scalar @rcsid == 9);

    $config{progname} = basename $0;		# this program's name
    $config{exitOnConflict} = 1;		# exit on conflicts - install only

    # These initialisation values are in quotes to ensure the perl -c check
    # passes. They are text values of the form xTEXTx which will be
    # replaced by sed as part of the make process.

    # Are superuser privileges required?
    $config{superuser} = 'xSUPERUSERx';

    # Preserve directory permissions on newly created directories?
    # Only if SUPERUSER is set to 1 in the Makefile.
    $config{preservePermissions} = 'xPRESERVEPERMSx';
    $config{preservePermissions} = 0 unless ($config{superuser});

    # Remove empty directories after an ungraft and remove conflicting
    # objects discovered during a prune?
    $config{deleteObjects} = 'xDELETEOBJECTSx';

    # default location of log file
    $config{logfile} = 'xLOGFILEx';

    # names of special graft control files
    $config{graftIgnore} = 'xGRAFT-IGNOREx';
    $config{graftExclude} = 'xGRAFT-EXCLUDEx';
    $config{graftInclude} = 'xGRAFT-INCLUDEx';

    # Should graft always ignore files and/or directories
    # specified by $config{graftNever}?
    $config{neverGraft} = 'xNEVERGRAFTx';

    # default package and target directories
    $config{packageDefault} = 'xPACKAGEDIRx';
    $config{target} = 'xTARGETDIRx';
    $config{targetTop} = $config{target};

    # pruned file suffix
    $config{prunedSuffix} = 'xPRUNED-SUFFIXx';

    # Verbosity is zero for the moment. Set by user with -v or -V options.
    $config{verbose} = 0;
    $config{veryVerbose} = 0;

    ###########################################################################
    #
    # Argument parsing

    usage() unless GetOptions(
				C	=> sub{$option{C} = 1    },
				D	=> sub{$option{D} = 1    },
				d	=> sub{$option{d} = 1    },
				i	=> sub{$option{i} = 1    },
				'l=s'	=> sub{$option{l} = $_[1]},
				n	=> sub{$option{n} = 1    },
				P	=> sub{$option{P} = 1    },
				p	=> sub{$option{p} = 1    },
				s	=> sub{$option{s} = 1    },
				't=s'	=> sub{$option{t} = $_[1]},
				u	=> sub{$option{u} = 1    },
				V	=> sub{$option{V} = 1    },
				v	=> sub{$option{v} = 1    },
			    );

    # User must supply one of the -d, -i or -p  options

    usage() unless (exists $option{d} or exists $option{i} or exists $option{p});

    # Options -d, -i and -p are mutually exclusive

    usage() if (
		    (exists $option{d} and exists $option{i})
		    or
		    (exists $option{d} and exists $option{p})
		    or
		    (exists $option{i} and exists $option{p})
		);

    if ($config{superuser})
    {
	# Silently ignore -P if the effective user is not root

	delete $option{P} if ($>);

	# -P is only useful with -i

	usage() if (exists $option{P} and (exists $option{d} or exists $option{p}));

	# -P and -u are mutally exclusive

	usage() if (exists $option{P} and exists $option{u});
    }

    # -C is only useful with -i

    usage() if (exists $option{C} and (exists $option{d} or exists $option{p}));

    # -D is only useful with -d or -p

    usage() if (exists $option{D} and exists $option{i});

    # -s and -t are mutually exclusive

    usage() if (exists $option{s} and exists $option{t});

    ###########################################################################
    #
    # Argument processing

    if (exists $option{l})
    {
	# Logfile name must be fully qualified and the directory in which
	# it lives must exist.

	$config{logfile} = $option{l};		# User supplied log file name

	unless (fullyqualified($config{logfile}))
	{
	    message(
		    tag	=> 'ERROR',
		    msg	=> "Log file $config{logfile} is not fully qualified.",
		);

	    usage();
	}

	my $dir = dirname $config{logfile};

	unless (-d $dir)
	{
	    message(
		    tag	=> 'ERROR',
		    msg	=> "Cannot create log file $config{logfile}. No such"
			       . " directory as $dir.",
		);

	    usage();
	}
    }

    if (exists $option{n})
    {
	++$config{verbose};			# -n implies very verbose
	++$config{veryVerbose};
	$config{exitOnConflict} = 0;		# no need to exit on conflicts
    }
    else
    {
	# How verbose is verbose?

	++$config{verbose} if (exists $option{v} or exists $option{V});
	++$config{veryVerbose} if (exists $option{V});
    }

    if (exists $option{t})
    {
	# Target directory must be fully qualified and it must also exist

	$config{target} = $option{t};
	$config{targetTop} = $config{target};

	unless (fullyqualified($config{target}))
	{
	    message(
		    tag	=> 'ERROR',
		    msg	=> "Target directory $config{target} is not fully qualified.",
		);

	    usage();
	}

	unless (-d $config{target})
	{
	    message(
		    tag	=> 'ERROR',
		    msg	=> "Target directory $config{target} does not exist.",
		);

	    usage();
	}
    }

    usage() unless (scalar @ARGV);		# Need package arguments

    # We do the toggles last. Otherwise the command line arguments would
    # affect the usage message which could confuse the punters. The toggles
    # could be coded as ternary operators but these are more readable and
    # obvious to me :)

    if (exists $option{C})			# Toggle never graft flag
    {
	if ($config{neverGraft})
	{
	    $config{neverGraft} = 0;		# Was set to 1 in Makefile
	}
	else
	{
	    $config{neverGraft} = 1;		# Was set to 0 in Makefile
	}
    }

    if ($config{neverGraft})
    {
	# List of files and/or directories graft may never examine.

	map {++$config{graftNever}{$_}} qw ( xGRAFT-NEVERx );
    }

    if (exists $option{D})			# Toggle delete directories flag
    {
	if ($config{deleteObjects})
	{
	    $config{deleteObjects} = 0;		# Was set to 1 in Makefile
	}
	else
	{
	    $config{deleteObjects} = 1;		# Was set to 0 in Makefile
	}
    }

    if ($config{superuser})
    {
	if (exists $option{P})				# Toggle preserve permissions flag
	{
	    if ($config{preservePermissions})
	    {
		$config{preservePermissions} = 0;	# Was set to 1 in Makefile
	    }
	    else
	    {
		$config{preservePermissions} = 1;	# Was set to 0 in Makefile
	    }
	}
    }

    # Disable superuser privileges if superuser was set to 1 in Makefile
    # and user specified -u on the command line.

    $config{superuser} = 0 if (exists $option{u} and $config{superuser});

    if ($config{superuser})
    {
	# Everything beyond this point requires superuser
	# privileges unless -n or -u was specified on the command line.

	die "Sorry, only the superuser can install or delete packages.\n"
	    unless ($> == 0 or exists $option{n});
    }

    # If everything succeeds, then exit with status 0. If a CONFLICT
    # arises, then exit with status 1. If the user supplied invalid command
    # line arguments the program has already exited with status 2. If one
    # or more packages does not exist then exit with status 3.

    $config{errorStatus} = 0;			# Set default exit status
}

sub install
{
    # For each directory in $source, create a directory in $target.
    # For each file in $source, create a symbolic link from $target.

    my %arg = @_;

    my $source = $arg{source};
    my $target = $arg{target};

    unless (chdir $source)
    {
	message(
		tag	=> 'ERROR',
		msg	=> "Could not change directories to $source: $!",
	    );

	return;
    }

    message(
	    tag	=> 'Processing',
	    msg	=> "$source",
	) if $config{verbose};

    # get a list of files and directories in this directory

    my %files;
    %files = files($source);

    my %directories;
    %directories = directories($source);

    # Don't process this directory if an ignore file exists

    if (exists $files{$config{graftIgnore}})
    {
	message(
		tag	=> 'BYPASS',
		msg	=> "$source - $config{graftIgnore} file found",
	    ) if $config{veryVerbose};

	return;
    }

    # If an include file exists, its contents should be a list of files
    # and/or directories to exclusively include in the graft.

    my %includes;
    my $exclusiveInclude = 0;

    if (exists $files{$config{graftInclude}})
    {
	%includes = cat($config{graftInclude});
	++$exclusiveInclude;

	message(
		tag	=> 'READING',
		msg	=> "include file $source/$config{graftInclude}",
	    ) if $config{veryVerbose};

	delete $files{$config{graftInclude}};
    }

    # If an exclude file exists, its contents should be a list of files
    # and/or directories to exclude from the graft. This takes
    # precedence over any included files.

    my %excludes;
    my $exclusiveExclude = 0;

    if (exists $files{$config{graftExclude}})
    {
	%excludes = cat($config{graftExclude});
	++$exclusiveExclude;

	message(
		tag	=> 'READING',
		msg	=> "exclude file $source/$config{graftExclude}",
	    ) if $config{veryVerbose};

	delete $files{$config{graftExclude}};

	# Explicit exclusion takes precedence over explicit inclusion

	if ($exclusiveInclude)
	{
	    $exclusiveInclude = 0;

	    message(
		    tag	=> 'IGNORE',
		    msg => "include file $source/$config{graftInclude}, overridden"
			   . " by exclude file $source/$config{graftExclude}"
		) if $config{veryVerbose};
	}
    }

    foreach my $file (sort keys %files)
    {
	if ($exclusiveInclude)
	{
	    if (exists $includes{$file})
	    {
		message(
			tag	=> 'INCLUDE',
			msg	=> "file $source/$file - listed in"
				   . " $source/$config{graftInclude}",
		    ) if $config{veryVerbose};
	    }
	    else
	    {
		message(
			tag	=> 'IGNORE',
			msg	=> "file $source/$file - not listed in"
				   . " $source/$config{graftInclude}",
		    ) if $config{veryVerbose};

		next;
	    }
	}

	if (exists $excludes{$file})
	{
	    message(
		    tag	=> 'EXCLUDE',
		    msg	=> "file $source/$file - listed in"
			   . " $source/$config{graftExclude}",
		) if $config{veryVerbose};

	    next;
	}

	if (exists $config{graftNever}{$file})
	{
	    message(
		    tag	=> 'EXCLUDE',
		    msg	=> "file $source/$file will never be grafted",
		) if $config{veryVerbose};

	    next;
	}

	if (-l "$target/$file")
	{
	    # Target file exists and is a symlink. If it is a symlink
	    # to the source file it can be ignored. Having this test
	    # first avoids any problems later where the target may be a
	    # symlink to the package file which is in turn a symlink to
	    # a non existent file. A -e test in this case fails as it
	    # uses stat() which will traverse the link(s).

	    my $link = readlink "$target/$file";

	    if ("$source/$file" eq $link)
	    {
		message(
			tag	=> 'NOP',
			msg	=> "$target/$file already linked to"
				   . " $source/$file",
		    ) if $config{veryVerbose};
	    }
	    else
	    {
		message(
			tag	=> 'CONFLICT',
			msg	=> "$target/$file is linked to something"
				   . " other than $source/$file"
				   . " ($target/$file -> $link)",
		    );

		logger(
			tag	=> 'IC',
			log	=> [ "$target/$file", 'invalid symlink' ],
		    ) unless (exists $option{n});

		exit 1 if $config{exitOnConflict};
	    }

	    next;
	}

	unless (-e "$target/$file")
	{
	    # Target file does not exist - so we can safely create
	    # a symbolic link for the target to the original.

	    message(
		    tag	=> 'SYMLINK',
		    msg	=> "$target/$file -> $source/$file",
		) if $config{veryVerbose};

	    # Make the symbolic link. If -n was specified, don't
	    # actually create anything, just report the action and move
	    # to the next file.

	    unless (exists $option{n})
	    {
		symlink "$source/$file", "$target/$file"
		    or die 'Failed to create symbolic link'
			   . " $target/$file -> $source/$file: $!\n";
	    }

	    next;
	}

	message(
		tag	=> 'CONFLICT',
		msg	=> "$target/$file already exists but is NOT a"
			   . " symlink to $source/$file",
	    );

	logger(
		tag	=> 'IC',
		log	=> [ "$target/$file", 'file exists' ],
	    ) unless (exists $option{n});

	exit 1 if $config{exitOnConflict};
    }

    foreach my $dir (sort keys %directories)
    {
	if (-f "$source/$dir/$config{graftIgnore}")
	{
	    # Explicitly ignore directories with ignore files

	    message(
		    tag	=> 'BYPASS',
		    msg	=> "$source/$dir - $config{graftIgnore} file found",
		) if $config{veryVerbose};

	    next;
	}

	if ($exclusiveInclude)
	{
	    if (exists $includes{$dir})
	    {
		message(
			tag	=> 'INCLUDE',
			msg	=> "directory $source/$dir - listed in"
				   . " $source/$config{graftInclude}",
		    ) if $config{veryVerbose};
	    }
	    else
	    {
		message(
			tag	=> 'IGNORE',
			msg	=> "directory $source/$dir - not listed"
				   . " in $source/$config{graftInclude}",
		    ) if $config{veryVerbose};
		next;
	    }
	}

	if (exists $excludes{$dir})
	{
	    message(
		    tag	=> 'EXCLUDE',
		    msg	=> "directory $source/$dir - listed in"
			   . " $source/$config{graftExclude}",
		) if $config{veryVerbose};

	    next;
	}

	if (exists $config{graftNever}{$dir})
	{
	    message(
		    tag	=> 'EXCLUDE',
		    msg	=> "directory $source/$dir will never be grafted",
		) if $config{veryVerbose};

	    next;
	}

	unless (-e "$target/$dir")
	{
	    # Target does not exist - so we can
	    # safely create the target directory.

	    message(
		    tag	=> 'MKDIR',
		    msg	=> "$target/$dir",
		) if $config{veryVerbose};

	    # Create directory (with the same permissions, owner and group
	    # as the original if specified by -P). If -n was specified,
	    # don't actually create anything, just report the action and
	    # move to the next directory.

	    unless (exists $option{n})
	    {
		if ($config{preservePermissions} and $config{superuser})
		{
		    my $mode;
		    my $uid;
		    my $gid;

		    # Only do this if superuser privileges are on.
		    # Otherwise it's bound to fail.

		    (undef, undef, $mode, undef, $uid, $gid, undef,
			undef, undef, undef, undef, undef, undef)
			= stat "$source/$dir";

		    mkdir "$target/$dir", $mode
			or die "Could not create $target/$dir: $!\n";

		    chown $uid, $gid, "$target/$dir"
			or die "Could not set ownership on $target/$dir: $!\n";
		}
		else
		{
		    mkdir "$target/$dir", 0755
			or die "Could not create $target/$dir: $!\n";
		}
	    }

	    # Recursively descend into this directory and repeat the
	    # process.

	    install(
		    source	=> "$source/$dir",
		    target	=> "$target/$dir",
		);

	    next;
	}

	if (-d "$target/$dir")
	{
	    # Target directory already exists. Recursively descend into the
	    # sub-directories.

	    message(
		    tag	=> 'NOP',
		    msg	=> "$source/$dir and $target/$dir are both directories",
		) if $config{veryVerbose};

	    install(
		    source	=> "$source/$dir",
		    target	=> "$target/$dir",
		);

	    next;
	}

	# Target already exists but is NOT a directory - conflict.

	message(
		tag	=> 'CONFLICT',
		msg	=> "$target/$dir already exists but is NOT"
			   . ' a directory!',
	    );

	logger(
		tag	=> 'IC',
		log	=> [ "$target/$dir", 'not a directory' ],
	    ) unless (exists $option{n});

	exit 1 if $config{exitOnConflict};
    }
}

sub logger
{
    # Write a message in the log file. Prepend each message with the system
    # time and program version number.

    my %msg = @_;

    $msg{tag} = sprintf("%s\t%s\t%s", time, $config{version}, $msg{tag});

    if (defined open LOGFILE, ">> $config{logfile}")
    {
	print LOGFILE join("\t", $msg{tag}, @{$msg{log}}), "\n";
	close LOGFILE;
    }
    else
    {
	message(
		tag	=> 'ERROR',
		msg	=> "Could not open log file $config{logfile}: $!.",
	    );

	$config{errorStatus} = 4 unless ($config{errorStatus});
    }
}

sub message
{
    # Display a message on STDOUT or STDERR

    my %msg = @_;

    my $tagLength = 12;		# Length of longest tag word.

    if (
	    $msg{tag} eq 'CONFLICT'
	    or
	    $msg{tag} eq 'ERROR'
	)
    {
	warn
		sprintf("%-${tagLength}.${tagLength}s ", $msg{tag}),
		$msg{msg},
		"\n";
    }
    else
    {
	print
		sprintf("%-${tagLength}.${tagLength}s ", $msg{tag}),
		$msg{msg},
		"\n";
    }
}

sub prune
{
    # Move or delete a file or directory

    my $object = shift;

    # Check for symlinks first. A symlink to a directory will pass a -d test.

    if (-l $object)
    {
	if ($config{deleteObjects})
	{
	    message(
		    tag	=> 'UNLINK',
		    msg	=> "$object",
		) if $config{veryVerbose};

	    unless (exists $option{n})
	    {
		unlink "$object"
		    or die "Could not unlink $object: $!\n";
	    }
	}
	else
	{
	    message(
		    tag	=> 'RENAME',
		    msg	=> "$object",
		) if $config{veryVerbose};

	    unless (exists $option{n})
	    {
		rename "$object", "${object}$config{prunedSuffix}"
		    or die "Could not rename $object to"
			   . " ${object}$config{prunedSuffix}: $!\n";
	    }
	}

	return;
    }

    if (-d $object)
    {
	if ($config{deleteObjects})
	{
	    if (opendir OBJ, "$object")
	    {
		my %files;

		foreach (readdir OBJ)
		{
		    next if /^\.\.?$/;		# ignore '.' and '..'
		    ++$files{$_};
		}

		closedir OBJ;

		if (scalar keys %files)
		{
		    message(
			    tag	=> 'ERROR',
			    msg => "Cannot remove $object/, renaming"
				   . ' instead. Directory not empty',
			);

		    message(
			    tag	=> 'RENAME',
			    msg	=> "$object",
			) if $config{veryVerbose};

		    unless (exists $option{n})
		    {
			rename "$object", "${object}$config{prunedSuffix}"
			    or die "Could not rename $object to"
				   . " ${object}$config{prunedSuffix}: $!\n";
		    }
		}
		else
		{
		    message(
			    tag	=> 'UNLINK',
			    msg	=> "$object",
			) if $config{veryVerbose};

		    unless (exists $option{n})
		    {
			rmdir "$object"
			    or die "Could not remove directory $object: $!\n";
		    }
		}
	    }
	    else
	    {
		message(
			tag	=> 'ERROR',
			msg	=> "Could not open $object/ for reading,"
				   . " renaming instead: $!",
		    );

		message(
			tag	=> 'RENAME',
			msg	=> "$object",
		    ) if $config{veryVerbose};

		unless (exists $option{n})
		{
		    rename "$object", "${object}$config{prunedSuffix}"
			or die "Could not rename $object to"
			       . " ${object}$config{prunedSuffix}: $!\n";
		}
	    }
	}
	else
	{
	    message(
		    tag	=> 'RENAME',
		    msg	=> "$object",
		) if $config{veryVerbose};

	    unless (exists $option{n})
	    {
		rename "$object", "${object}$config{prunedSuffix}"
		    or die "Could not rename $object to"
			   . " ${object}$config{prunedSuffix}: $!\n";
	    }
	}

	return;
    }

    # Anything beyond here is neither a symlink nor a directory

    if ($config{deleteObjects})
    {
	message(
		tag	=> 'UNLINK',
		msg	=> "$object",
	    ) if $config{veryVerbose};

	unless (exists $option{n})
	{
	    unlink "$object"
		or die "Could not unlink $object: $!\n";
	}
    }
    else
    {
	message(
		tag	=> 'RENAME',
		msg	=> "$object",
	    ) if $config{veryVerbose};

	unless (exists $option{n})
	{
	    rename "$object", "${object}$config{prunedSuffix}"
		or die "Could not rename $object to"
		       . " ${object}$config{prunedSuffix}: $!\n";
	}
    }
}

sub stripslashes
{
    # Strip leading and trailing slashes and whitespace from user supplied
    # package names. Some shells will put a trailing slash onto directory
    # names when using file completion - Bash for example.
    #
    # Also, Perl's builtin File::Basename::basename() will return an
    # empty string for a slash terminated directory, unlike the command
    # line version which returns the last directory component.

    my $string = shift;

    $string =~ s#^\s*/*$#/#;
    $string =~ s#/*\s*$##;
    return $string;
}

sub uninstall
{
    # For each file in $source, remove the corresponding symbolic link
    # from $target. Directories may be deleted depending on the status
    # of $config{deleteObjects}. If the -p option was used instead of -d
    # then prune conflicting files from the target rather than delete
    # previously grafted links.

    my %arg = @_;

    my $source = $arg{source};
    my $target = $arg{target};

    unless (chdir $source)
    {
	message(
		tag	=> 'ERROR',
		msg	=> "Could not change directories to $source: $!",
	    );

	return;
    }

    message(
	    tag	=> 'Processing',
	    msg	=> "$source",
	) if $config{verbose};

    # get a list of files and directories in this directory

    my %files;
    %files = files($source);

    my %directories;
    %directories = directories($source);

    # Ignore any control files

    delete $files{$config{graftIgnore}};
    delete $files{$config{graftInclude}};
    delete $files{$config{graftExclude}};

    foreach my $file (keys %files)
    {
	if (-l "$target/$file")
	{
	    # Target file exists and is a symlink. If it is a symlink to
	    # the source file it can be ignored. Having this test first
	    # avoids any problems later where the target may be a symlink
	    # to the package file which is in turn a symlink to a non
	    # existent file. A -e test in this case fails as it uses stat()
	    # which will traverse the link(s).

	    my $link = readlink "$target/$file";

	    if ("$source/$file" eq $link)
	    {
		unless (exists $option{p})
		{
		    # If -n was specified, don't actually remove anything,
		    # just report the action and move to the next file.

		    message(
			    tag	=> 'UNLINK',
			    msg	=> "$target/$file",
			) if $config{veryVerbose};

		    unless (exists $option{n})
		    {
			unlink "$target/$file"
			    or message(
				    tag	=> 'ERROR',
				    msg	=> "Could not unlink $target/$file: $!",
				);
		    }
		}

		next;
	    }
	    else
	    {
		if (exists $option{p})
		{
		    prune("$target/$file");
		}
		else
		{
		    message(
			    tag	=> 'CONFLICT',
			    msg => "$target/$file is linked to something"
				   . " other than $source/$file"
				   . " ($target/$file -> $link)",
			);

		    logger(
			    tag	=> 'DC',
			    log	=> [ "$target/$file", 'invalid symlink' ],
			) unless (exists $option{n});
		}
	    }

	    next;
	}

	unless (-e "$target/$file")
	{
	    unless (exists $option{p})
	    {
		# Target file does not exist - package may not have been
		# installed correctly or file is in xGRAFT-EXCLUDEx or
		# directory has a xGRAFT-IGNOREx file.

		message(
			tag	=> 'NOP',
			msg	=> "$target/$file does not exist",
		    ) if $config{veryVerbose};
	    }

	    next;
	}

	if (exists $option{p})
	{
	    prune("$target/$file");
	}
	else
	{
	    message(
		    tag	=> 'CONFLICT',
		    msg => "$target/$file already exists but is NOT a"
			   . " symlink to $source/$file",
		);

	    logger(
		    tag	=> 'DC',
		    log	=> [ "$target/$file", 'file exists' ],
		) unless (exists $option{n});
	}
    }

    # Recursively descend into this directory and repeat the process.

    foreach my $dir (sort keys %directories)
    {
	uninstall(
		source	=> "$source/$dir",
		target	=> "$target/$dir",
	    );
    }

    return if exists $option{p};	# No need to do empty directory
					# check in prune mode

    # Check to see if the target directory is now empty. If so flag ask the
    # user to manually delete it if so desired. Delete the directory if
    # $config{deleteObjects} is true.

    if (-d "$target")
    {
	unless (chdir $target)
	{
	    message(
		    tag	=> 'ERROR',
		    msg	=> "Could not change directories to $target: $!",
		);

	    return;
	}

	%files = files($target);
	%directories = directories($target);

	unless (scalar keys %files or scalar keys %directories)
	{
	    # Don't delete the top most target directory

	    unless ($target eq $config{targetTop})
	    {
		unless ($config{deleteObjects})
		{
		    message(
			    tag	=> 'EMPTY',
			    msg => "$target/ is now empty. Delete manually"
				   . ' if necessary.',
			);
		}
		else
		{
		    message(
			    tag	=> 'RMDIR',
			    msg	=> "$target/",
			);

		    unless (exists $option{n})
		    {

			unless (chdir '..')
			{
			    message(
				    tag	=> 'ERROR',
				    msg => 'Could not change directories'
					   . " to $target/..: $!",
				);

			    return;
			}

			rmdir $target
			    or message(
				    tag	=> 'ERROR',
				    msg => 'Cannot remove directory'
					   . " $target: $!",
				);
		    }
		}
	    }
	}
    }
}

sub usage
{
    my $nopriv;
    my $priv;

    if ($config{superuser})
    {
	$priv = 'Requires superuser privileges.';
	$nopriv = 'Does not require superuser privileges.';
    }
    else
    {
	$priv = '';
	$nopriv = '';
    }

    print << "EOF" if $config{superuser};

$config{progname}: Version $config{version}

Usage:
  $config{progname} -i [-C] [-P|u] [-l log] [-n] [-v|V] [-s|-t target] package package ...
  $config{progname} -d [-D] [-u] [-l log] [-n] [-v|V] [-s|-t target] package package ...
  $config{progname} -p [-D] [-u] [-l log] [-n] [-v|V] [-s|-t target] package package ...

  -i            Install packages. $priv
                Cannot be used with -d or -p options.
EOF

    print << "EOF" unless ($config{superuser});

$config{progname}: Version $config{version}

Usage:
  $config{progname} -i [-C] [-l log] [-n] [-v|V] [-s|-t target] package package ...
  $config{progname} -d [-D] [-l log] [-n] [-v|V] [-s|-t target] package package ...
  $config{progname} -p [-D] [-l log] [-n] [-v|V] [-s|-t target] package package ...

  -i            Install packages. $priv
                Cannot be used with -d or -p options.
EOF

    if ($config{neverGraft})
    {
	print << "EOF";
  -C            Disable the automatic exclusion of files and/or
  		directories that match:
EOF

        print "\t\t    ";

	if (scalar keys %{$config{autoIgnore}})
	{
	    print join(' ', keys %{$config{autoIgnore}}), "\n";
	}
	else
	{
	    print "*** No file or directory names to match ***\n";
	}
    }
    else
    {
	print << "EOF";
  -C            Force the automatic exclusion of files and/or
  		directories that match:
EOF

        print "\t\t    ";

	if (scalar keys %{$config{autoIgnore}})
	{
	    print join(' ', keys %{$config{autoIgnore}}), "\n";
	}
	else
	{
	    print "*** No file or directory names to match ***\n";
	}
    }

    if ($config{superuser})
    {
	if ($config{preservePermissions})
	{
	    print << "EOF";
  -P            Do not preserve ownership and permissions when creating
                directories. Can only be used with the -i option.
                Cannot be used with the -u option.
EOF
	}
	else
	{
	print << "EOF";
  -P            Preserve ownership and permissions when creating
                directories. Can only be used with the -i option.
                Cannot be used with the -u option.

                Silently ignored if the effective user is not root.
EOF
	}
    }

    print << "EOF";
  -d            Delete packages. $priv
                Cannot be used with -i or -p options.
  -p            Prune files that will conflict with the grafting of the
                named packages. $priv
                Cannot be used with -d or -i options.
EOF

    if ($config{deleteObjects})
    {
	print << "EOF";
  -D            When used with the -d option, do not remove directories
                made empty by package deletion. When used with the -p
                option, rename conflicting files or directories to
                file$config{prunedSuffix} instead of removing them.
                Cannot be used with the -i option.
EOF
    }
    else
    {
	print << "EOF";
  -D            When used with the -d option, remove directories made
                empty by package deletion. When used with the -p
                option, remove conflicting files or directories
                instead of renaming them as file$config{prunedSuffix}. If
                the directory is not empty it will be renamed as
                dir$config{prunedSuffix}. Cannot be used with the -i option.
EOF
    }

    print << "EOF" if $config{superuser};
  -u            Superuser privileges are not required to install, delete
                or prune packages. Cannot be used with the -P option.
EOF

    print << "EOF";
  -l log        Use the named file as the log file instead of the
                default log file. The log file name must be fully
                qualified. The log file is not used if the -n option
                is also supplied. Default: xLOGFILEx
  -n            Print list of operations but do NOT perform them.
                Automatically implies the very verbose option.
EOF

    print << "EOF" if $config{superuser};
                $nopriv
EOF

    print << "EOF";
  -v            Be verbose.
  -V            Be very verbose.
  -s            Stow/Depot compatibility mode. Infer the graft target
                directory from the package installation directory in
                the manner of Stow and Depot. Cannot be used with the
                -t option.
  -t target     Use the named directory as the graft target directory
                rather than the default target directory. The target
                directory must be fully qualified. Cannot be used with
                the -s option. Default: xTARGETDIRx
  package       Operate on the named packages. If the package name is
                not fully qualified, the default package installation
                directory will be prepended to the named package.
                Default: xPACKAGEDIRx
EOF

    exit 2;
}
