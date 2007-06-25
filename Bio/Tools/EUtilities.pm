# $Id$
#
# BioPerl module for Bio::Tools::EUtilities
#
# Cared for by Chris Fields
#
# Copyright Chris Fields
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=head1 NAME

Bio::Tools::EUtilities - NCBI eutil XML parsers

=head1 SYNOPSIS

  # from file or fh

    my $parser = Bio::Tools::EUtilities->new(
                                       -eutil    => 'einfo',
                                       -file     => 'output.xml'
                                        );
  
  # or HTTP::Response object...
    
    my $parser = Bio::Tools::EUtilities->new(
                                       -eutil => 'esearch',
                                       -response => $response 
                                        );
  
  # esearch, esummary, elink
  
    @ids = $parser->get_ids(); # returns array or array ref of IDs

  # egquery, espell
  
    $term = $parser->get_term(); # returns array or array ref of IDs
  
  # elink, einfo
  
    $db = $parser->get_database(); # returns database
  
  # Query-related methods (esearch, egquery, espell data)
  # eutil data centered on use of search terms
    
    my $ct = $parser->get_count; # uses optional database for egquery count
    my $translation = $parser->get_count;
    
    my $corrected = $parser->get_corrected_query; # espell
    
    while (my $gquery = $parser->next_GlobalQuery) {
       # iterates through egquery data
    }
  
  # Info-related methods (einfo data)
  # database-related information
  
    my $desc = $parser->get_description;  
    my $update = $parser->get_last_update;
    my $nm = $parser->get_menu_name;
    my $ct = $parser->get_record_count;
  
    while (my $field = $parser->next_FieldInfo) {...}
    while (my $field = $parser->next_LinkInfo) {...}
  
  # History methods (epost data, some data returned from elink)
  # data which enables one to retrieve and query against user-stored information on the NCBI server
  
    if ($parser->has_history) {
        # use parser as direct input in future queries
    }
    
    my ($webenv, $querykey) = $parser->history;
  
  # Bio::Tools::EUtilities::Summary (esummary data)
  # information on a specific database record
  
    # retrieve nested docsum data
    while (my $docsum = $parser->next_DocSum) {
        print "ID:",$docsum->get_ids,"\n";
        while (my $item = $docsum->next_Item) {
            # do stuff here...
            while (my $listitem = $docsum->next_ListItem) {
                # do stuff here...
                while (my $listitem = $docsum->next_Structure) {
                    # do stuff here...
                }
            }
        }
    }
  
    # retrieve flattened item list per DocSum
    while (my $docsum = $parser->next_DocSum) {
        my @items = $docsum->get_all_DocSum_Items; 
    }

  # Bio::Tools::EUtilities::Link (elink data)
  # data retrieved using links between related information in databases
  
    # still working on new API
    
=head1 DESCRIPTION

Parses NCBI eutils XML output for retrieving IDs and other information. Part of
the BioPerl EUtilities system.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the
evolution of this and other Bioperl modules. Send
your comments and suggestions preferably to one
of the Bioperl mailing lists. Your participation
is much appreciated.

  bioperl-l@lists.open-bio.org               - General discussion
  http://www.bioperl.org/wiki/Mailing_lists  - About the mailing lists

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to
help us keep track the bugs and their resolution.
Bug reports can be submitted via the web.

  http://bugzilla.open-bio.org/

=head1 AUTHOR 

Email cjfields at uiuc dot edu

=head1 APPENDIX

The rest of the documentation details each of the
object methods. Internal methods are usually
preceded with a _

=cut

# Let the code begin...

package Bio::Tools::EUtilities;
use strict;
use warnings;

use base qw(Bio::Root::IO Bio::Tools::EUtilities::HistoryI);

use XML::Simple;
use Data::Dumper;

=head2 Constructor methods

=cut

=head2 new

 Title    : new
 Usage    : my $parser = Bio::Tools::EUtilities->new(-file => 'my.xml',
                                                    -eutil => 'esearch');
 Function : create Bio::Tools::EUtilities instance
 Returns  : new Bio::Tools::EUtilities instance
 Args     : -file/-fh - File or filehandle
            -eutil    - eutil parser to use (supports all but efetch)
            -response - HTTP::Response object (optional)

=cut

{

my %DATA_MODULE = (
    'esearch'   => 'Query',
    'egquery'   => 'Query',
    'espell'    => 'Query',
    'epost'     => 'History',
    'elink'     => 'Link',
    'einfo'     => 'Info',
    'esummary'  => 'Summary',
    );

sub new {
    my($caller,@args) = @_;
    my $class = ref $caller || $caller;
    if ($class =~ m{Bio::Tools::EUtilities::(\S+)}) {
        my ($self) = $class->SUPER::new(@args);
        $self->_initialize(@args);
        return $self;
    } else {
        my %param = @args;
		@param{ map { lc $_ } keys %param } = values %param; # lowercase keys
        my $eutil = $param{'-eutil'} || $class->throw("Need eutil to make instance");
        return unless( $class->_load_eutil_module( $DATA_MODULE{$eutil}) );
        return "Bio::Tools::EUtilities::$DATA_MODULE{$eutil}"->new(-datatype => lc $DATA_MODULE{$eutil},
                                                                   -eutil => $eutil,
                                                                   @args);
    }
}

sub _initialize {
    my ($self, @args) = @_;
    my ($response, $type, $eutil, $cache, $lazy) =
    $self->_rearrange([qw(RESPONSE DATATYPE EUTIL CACHE_RESPONSE LAZY)], @args);
    $lazy ||= 0;
    $cache ||= 0;
    $self->datatype($type);
    $self->eutil($eutil);
    $response  && $self->response($response);
    $self->cache_response($cache);
    
    # lazy parsing only implemented for elink and esummary (where returned data
    # can be quite long). Also, no point to parsing lazily when the data is
    # already in memory in an HTTP::Response object, so turn it off and chunk
    # the Response object after parsing.
    
    $lazy = 0 if ($response) || ($eutil ne 'elink' && $eutil ne 'esummary');
    # setting parser to 'lazy' mode is permanent (can't reset later)
    $self->{'_lazy'} = $lazy;
    $self->{'_parsed'} = 0;
}

}

=head1 Bio::Tools::EUtilities methods

=head2 cache_response

 Title    : cache_response
 Usage    : $parser->cache_response(1)
 Function : sets flag to cache response object (off by default)
 Returns  : value eval'ing to TRUE or FALSE
 Args     : value eval'ing to TRUE or FALSE
 Note     : must be set prior to any parsing run
 
=cut

sub cache_response {
    my ($self, $cache) = @_;
    if (defined $cache) {
        $self->{'_cache_response'} = ($cache) ? 1 : 0;
    }
    return $self->{'_cache_response'};
}

=head2 response

 Title    : response
 Usage    : my $response = $parser->response;
 Function : Get/Set HTTP::Response object
 Returns  : HTTP::Response 
 Args     : HTTP::Response
 Note     : to prevent object from destruction set cache_response() to TRUE

=cut

sub response {
    my ($self, $response) = @_;
    if ($response) {
        $self->throw('Not an HTTP::Response object') unless (ref $response && $response->isa('HTTP::Response'));
        $self->{'_response'} = $response; 
    }
    return $self->{'_response'};
}

=head2 data_parsed

 Title    : data_parsed
 Usage    : if ($parser->data_parsed) {...}
 Function : returns TRUE if data has been parsed
 Returns  : value eval'ing to TRUE or FALSE
 Args     : none (set within parser)
 Note     : mainly internal method (set in case user wants to check
            whether parser is exhausted).

=cut

sub data_parsed {
    return shift->{'_parsed'};
}

=head2 is_lazy

 Title    : is_lazy
 Usage    : if ($parser->is_lazy) {...}
 Function : returns TRUE if parser is set to lazy parsing mode
            (only affects elink/esummary)
 Returns  : Boolean
 Args     : none
 Note     : Permanently set in constructor.

=cut

sub is_lazy {
    return shift->{'_lazy'};
}

=head2 parse_data

 Title    : parse_data
 Usage    : $parser->parse_data
 Function : direct call to parse data; normally implicitly called
 Returns  : none
 Args     : none

=cut

{
my %EUTIL_DATA = (
    'esummary'  => [qw(DocSum Item)],
    'epost'     => [],
    'egquery'   => [],
    'einfo'     => [qw(Field Link)],
    'elink'     => [qw(LinkSet LinkSetDb LinkSetDbHistory IdUrlSet 
                        Id IdLinkSet ObjUrl Link LinkInfo)],
    'espell'    => [qw(Original Replaced)],
    'esearch'   => [qw(Id)],
    );

sub parse_data {
    my $self = shift;
    my $eutil = $self->eutil;
    my $xs = XML::Simple->new();
    my $response = $self->response ? $self->response :
                   $self->_fh      ? $self->_fh      :
        $self->throw('No response or stream specified');
    my $simple = ($eutil eq 'espell') ?
            $xs->XMLin($self->_fix_espell($response), forcearray => $EUTIL_DATA{$eutil}) :
        ($response && $response->isa("HTTP::Response")) ?
            $xs->XMLin($response->content, forcearray => $EUTIL_DATA{$eutil}) :
            $xs->XMLin($response, forcearray => $EUTIL_DATA{$eutil});
    # check for errors
    if ($simple->{ERROR}) {
        my $error = $simple->{ERROR};
        $self->throw("NCBI $eutil nonrecoverable error: ".$error) unless ref $error;
    }
    if ($simple->{InvalidIdList}) {
        $self->warn("NCBI $eutil error: Invalid ID List".$simple->{InvalidIdList});
        return;
    }    
    if ($simple->{ErrorList} || $simple->{WarningList}) {
        my %errorlist = %{ $simple->{ErrorList} } if $simple->{ErrorList};
        my %warninglist = %{ $simple->{WarningList} } if $simple->{WarningList};
        my ($err_warn);
        for my $key (sort keys %errorlist) {
            my $messages = join("\n",grep {!ref $_} @{$errorlist{$key}});
            $err_warn .= "Error : $key = $messages";
        }    
        for my $key (sort keys %warninglist) {
            my $messages = join("\n",grep {!ref $_} @{$warninglist{$key}});
            $err_warn .= "Warning : $key = $messages";
        }
        chomp($err_warn);
        $self->warn("NCBI $eutil Errors/Warnings:\n".$err_warn)
        # don't return as some data may still be usefule
    }
    delete $self->{'_response'} unless $self->cache_response;
    $self->{'_parsed'} = 1;    
    $self->_add_data($simple);
}

# implemented only for elink/esummary

sub parse_chunk {
    my $self = shift;
    my $eutil = $self->eutil;
    my $tag = $eutil eq 'elink'    ? 'LinkSet' :
              $eutil eq 'esummary' ? 'DocSum'  :
              $self->throw("Only eutil elink/esummary use parse_chunk()");
    my $xs = XML::Simple->new();
    if ($self->response) {
        $self->throw("Lazy parsing not implemented for HTTP::Response data yet");
        delete $self->{'_response'} if !$self->cache_response && $self->data_parsed;
    } else { # has to be a file/filehandle
        my $fh = $self->_fh;
        my ($chunk, $seendoc, $line);
        CHUNK:
        while ($line = <$fh>) {
            next unless $seendoc || $line =~ m{^<$tag>};
            $seendoc = 1;
            $chunk .= $line;
            last if $line =~ m{^</$tag>};
        }
        if (!defined $line) {
            $self->{'_parsed'} = 1;
            return;
        }
        $self->_add_data(
            $xs->XMLin($chunk, forcearray => $EUTIL_DATA{$eutil}, KeepRoot => 1)
            );
    }
}

}

=head1 Bio::Tools::EUtilities::EUtilDataI methods

=head2 eutil

 Title    : eutil
 Usage    : $eutil->$foo->eutil
 Function : Get/Set eutil
 Returns  : string
 Args     : string (eutil)
 Throws   : on invalid eutil
 
=cut

=head2 datatype

 Title    : datatype
 Usage    : $type = $foo->datatype;
 Function : Get/Set data object type
 Returns  : string
 Args     : string

=cut

=head1 Bio::Tools::EUtilities::HistoryI methods

These are defined in the HistoryI interface

=head2 history

 Title    : history
 Usage    : my ($webenv, $qk) = $hist->history
 Function : returns two-element list of webenv() and query_key()
 Returns  : array
 Args     : none

=cut

=head2 get_webenv

 Title    : get_webenv
 Usage    : my $webenv = $hist->get_webenv
 Function : returns web environment key needed to retrieve results from
            NCBI server
 Returns  : string (encoded key)
 Args     : none

=cut

=head2 get_query_key

 Title    : get_query_key
 Usage    : my $qk = $hist->get_query_key
 Function : returns query key (integer) for the history number for this session
 Returns  : integer
 Args     : none

=cut

=head2 has_history

 Title    : has_history
 Usage    : if ($hist->has_history) {...}
 Function : returns TRUE if full history (webenv, query_key) is present 
 Returns  : BOOLEAN, value eval'ing to TRUE or FALUE
 Args     : none

=cut

=head1 Methods useful for multiple eutils

=head2 get_ids

 Title    : get_ids
 Usage    : my @ids = $parser->get_ids
 Function : returns array or array ref of requestes IDs
 Returns  : array or array ref (based on wantarray)
 Args     : [conditional] not required except when running elink queries against
            multiple databases. In case of the latter, the database name is
            optional (but recommended) when retrieving IDs as the ID list will
            be globbed together. If a db name isn't provided a warning is issued
            as a reminder.

=cut

sub get_ids {
    my ($self, $request) = @_;
    my $eutil = $self->eutil;
    if ($self->is_lazy) {
        $self->warn('get_ids() not implemented when using lazy mode');
        return;
    }
    $self->parse_data unless $self->data_parsed;
    if ($eutil eq 'esearch') {
        return wantarray && $self->{'_id'} ? @{ $self->{'_id'} } : $self->{'_id'} ;
    } elsif ($eutil eq 'elink')  {
        my @ids;
        if ($request) {
            if (ref $request eq 'CODE') {
                push @ids, map {$_->get_ids }
                    grep { $request->($_) } $self->get_LinkSets;
            } else {
                push @ids, map {$_->get_ids }
                    grep {$_->get_dbto eq $request} $self->get_LinkSets;
            }
        } else {
            $self->warn('Multiple database present, IDs will be globbed together')
                if $self->get_linked_databases > 1;
            push @ids, map {$_->get_ids } $self->get_LinkSets;
        }
        return wantarray ? @ids : \@ids;
    } elsif ($eutil eq 'esummary') {
        unless (exists $self->{'_id'}) {
            push @{$self->{'_id'}}, map {$_->get_id } $self->get_DocSums;
        }
        return wantarray ? @{$self->{'_id'}} : $self->{'_id'};        
    } 
}

=head2 get_database

 Title    : get_database
 Usage    : my $db = $info->get_database;
 Function : returns database name (eutil-compatible)
 Returns  : string
 Args     : none
 Note     : implemented for einfo and espell
 
=cut

sub get_database {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    if ($self->eutil eq 'einfo') {
        return $self->{'_dbname'};
    } else {
        return $self->{'_database'};
    }
}

=head2 get_db (alias for get_database)

=cut

sub get_db {
    return shift->get_database;
}

=head1 Query-related methods

=head2 get_count

 Title    : get_count
 Usage    : my $ct = $parser->get_count
 Function : returns the count (hits for a search)
 Returns  : integer
 Args     : [CONDITIONAL] string with database name - used to retrieve
            count from specific database when using egquery

=cut

sub get_count {
    my ($self, $db) = @_;
    $self->parse_data unless $self->data_parsed;
    # egquery
    if ($self->datatype eq 'multidbquery') {
        if (!$db) {
            $self->warn('Must specify database to get count from');
            return;
        }
        my ($gq) = grep {$_->get_database eq $db} $self->get_GlobalQueries;
        $gq && return $gq->get_count;
        $self->warn("Unknown database $db");
        return;
    } else {
        return $self->{'_count'};
    }
}

=head2 get_queried_databases

 Title    : get_queried_databases
 Usage    : my @dbs = $parser->get_queried_databases
 Function : returns list of databases searched with global query
 Returns  : array of strings
 Args     : none
 Note     : predominately used for egquery; if used with other eutils will
            return a list with the single database

=cut

sub get_queried_databases {
    my ($self, $db) = @_;
    $self->parse_data unless $self->data_parsed;
    # egquery
    my @dbs = ($self->datatype eq 'multidbquery') ?
        map {$_->get_database} $self->get_GlobalQueries :
        $self->get_database;
    return @dbs;
}

=head2 get_term

 Title   : get_term
 Usage   : $st = $qd->get_term;
 Function: retrieve the term for the global search
 Returns : string
 Args    : none

=cut

# egquery and espell

sub get_term {
    my ($self, @args) = @_;
    $self->parse_data unless $self->data_parsed;
    return $self->{'_term'};
}

=head2 get_translation_from

 Title   : get_translation_from
 Usage   : $string = $qd->get_translation_from();
 Function: portion of the original query replaced with translated_to()
 Returns : string
 Args    : none

=cut

# esearch

sub get_translation_from {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    return $self->{'_translation'}->{'From'};
}

=head2 get_translation_to

 Title   : get_translation_to
 Usage   : $string = $qd->get_translation_to();
 Function: replaced string used in place of the original query term in translation_from()
 Returns : string
 Args    : none

=cut

sub get_translation_to {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    return $self->{'_translation'}->{'To'};
}

=head2 get_retstart

 Title   : get_retstart
 Usage   : $start = $qd->get_retstart();
 Function: retstart setting for the query (either set or NCBI default)
 Returns : Integer
 Args    : none

=cut

sub get_retstart {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;    
    return $self->{'_retstart'};
}

=head2 get_retmax

 Title   : get_retmax
 Usage   : $max = $qd->get_retmax();
 Function: retmax setting for the query (either set or NCBI default)
 Returns : Integer
 Args    : none

=cut

sub get_retmax {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;    
    return $self->{'_retmax'};
}

=head2 get_query_translation

 Title   : get_query_translation
 Usage   : $string = $qd->get_query_translation();
 Function: returns the translated query used for the search (if any)
 Returns : string
 Args    : none
 Note    : this differs from the original term.

=cut

sub get_query_translation {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    return $self->{'_querytranslation'};
}

=head2 get_corrected_query

 Title    : get_corrected_query
 Usage    : my $cor = $eutil->get_corrected_query;
 Function : retrieves the corrected query when using espell
 Returns  : string 
 Args     : none

=cut

sub get_corrected_query {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    return $self->{'_correctedquery'};
}

=head2 get_replaced_terms

 Title    : get_replaced_terms
 Usage    : my $term = $eutil->get_replaced_term
 Function : returns array of strings replaced in the query
 Returns  : string 
 Args     : none

=cut

sub get_replaced_terms {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    if ($self->{'_spelledquery'} && $self->{'_spelledquery'}->{Replaced}) {
        ref $self->{'_spelledquery'}->{Replaced} ?
        return @{ $self->{'_spelledquery'}->{Replaced} } : return;
    }
}

=head2 next_GlobalQuery

 Title    : next_GlobalQuery
 Usage    : while (my $query = $eutil->next_GlobalQuery) {...}
 Function : iterates through the queries returned from an egquery search
 Returns  : GlobalQuery object
 Args     : none

=cut

sub next_GlobalQuery {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;    
    $self->{'_globalqueries_it'} = $self->generate_iterator('globalqueries')
        if (!exists $self->{'_globalqueries_it'});
    $self->{'_globalqueries_it'}->();
}

=head2 get_GlobalQueries

 Title    : get_GlobalQueries
 Usage    : @queries = $eutil->get_GlobalQueries
 Function : returns list of GlobalQuery objects
 Returns  : array of GlobalQuery objects
 Args     : none

=cut

sub get_GlobalQueries {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    ref $self->{'_globalqueries'} ? return @{ $self->{'_globalqueries'} } : return ();
}

=head1 Summary-related methods

=head2 next_DocSum

 Title    : next_DocSum
 Usage    : while (my $ds = $esum->next_DocSum) {...}
 Function : iterate through DocSum instances
 Returns  : single Bio::Tools::EUtilities::Summary::DocSum
 Args     : none yet

=cut

sub next_DocSum {
    my $self = shift;
    if(!$self->data_parsed && !$self->is_lazy) {
        $self->parse_data;
    }
    $self->{'_docsums_it'} = $self->generate_iterator('docsums')
        if (!exists $self->{'_docsums_it'});
    $self->{'_docsums_it'}->();
}

=head2 get_DocSums

 Title    : get_DocSums
 Usage    : my @docsums = $esum->get_DocSums
 Function : retrieve a list of DocSum instances
 Returns  : array of Bio::Tools::EUtilities::Summary::DocSum
 Args     : none

=cut

sub get_DocSums {
    my $self = shift;
    if ($self->is_lazy) {
        $self->warn('get_DocSums() not implemented when using lazy mode');
        return ();
    }
    $self->parse_data unless $self->data_parsed;
    return ref $self->{'_docsums'} ? @{ $self->{'_docsums'} } : return ();
}

=head1 Info-related methods

=head2 get_available_databases

 Title    : get_available_databases
 Usage    : my @dbs = $info->get_available_databases
 Function : returns list of available eutil-compatible database names
 Returns  : Array of strings 
 Args     : none

=cut

sub get_available_databases {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    ($self->{'_available_databases'}) ?
        return @{($self->{'_available_databases'})} :
        return ();
}

=head2 get_record_count

 Title    : get_record_count
 Usage    : my $ct = $eutil->get_record_count;
 Function : returns database record count
 Returns  : integer
 Args     : none

=cut

sub get_record_count {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    return $self->{'_count'}
}

=head2 get_last_update

 Title    : get_last_update
 Usage    : my $time = $info->get_last_update;
 Function : returns string containing time/date stamp for last database update
 Returns  : integer
 Args     : none

=cut

sub get_last_update {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    return $self->{'_lastupdate'}
}

=head2 get_menu_name

 Title    : get_menu_name
 Usage    : my $nm = $info->get_menu_name;
 Function : returns string of database menu name
 Returns  : string
 Args     : none
 
=cut

sub get_menu_name {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;    
    exists $self->{'_menuname'} ? return $self->{'_menuname'} :
    exists $self->{'_menu'} ? return $self->{'_menu'} :
    return;
}

=head2 get_description

 Title    : get_description
 Usage    : my $desc = $info->get_description;
 Function : returns database description
 Returns  : string
 Args     : none

=cut

sub get_description {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;
    return $self->{'_description'};
}

=head2 next_FieldInfo

 Title    : next_FieldInfo
 Usage    : while (my $field = $info->next_FieldInfo) {...}
 Function : iterate through FieldInfo objects
 Returns  : Field object
 Args     : none
 Note     : uses callback() for filtering if defined for 'fields'
 
=cut

sub next_FieldInfo {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;    
    $self->{'_fieldinfo_it'} = $self->generate_iterator('fieldinfo')
        if (!exists $self->{'_fieldinfo_it'});
    $self->{'_fieldinfo_it'}->();
}

=head2 get_FieldInfo

 Title    : get_FieldInfo
 Usage    : my @fields = $info->get_FieldInfo;
 Function : returns list of FieldInfo objects
 Returns  : array (FieldInfo objects)
 Args     : none

=cut

sub get_FieldInfo {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;        
    return ref $self->{'_fieldinfo'} ? @{ $self->{'_fieldinfo'} } : return ();
}

*get_FieldInfos = \&get_FieldInfo;

=head2 next_LinkInfo

 Title    : next_LinkInfo
 Usage    : while (my $link = $info->next_LinkInfo) {...}
 Function : iterate through LinkInfo objects
 Returns  : LinkInfo object
 Args     : none
 
=cut

sub next_LinkInfo {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;    
    $self->{'_linkinfo_it'} = $self->generate_iterator('linkinfo')
        if (!exists $self->{'_linkinfo_it'});
    $self->{'_linkinfo_it'}->();
}

=head2 get_LinkInfo

 Title    : get_LinkInfo
 Usage    : my @links = $info->get_LinkInfo;
 Function : returns list of LinkInfo objects
 Returns  : array (LinkInfo objects)
 Args     : none

=cut

sub get_LinkInfo {
    my $self = shift;
    $self->parse_data unless $self->data_parsed;        
    return ref $self->{'_linkinfo'} ? @{ $self->{'_linkinfo'} } : return ();
}

*get_LinkInfos = \&get_LinkInfo;

=head1 Bio::Tools::EUtilities::Link-related methods

=head2 next_LinkSet

 Title    : next_LinkSet
 Usage    : while (my $ls = $eutil->next_LinkSet {...}
 Function : 
 Returns  : 
 Args     : 

=cut

sub next_LinkSet {
    my $self = shift;
    #$self->parse_data unless $self->data_parsed;
    if(!$self->data_parsed && !$self->is_lazy) {
        $self->parse_data;
    }
    $self->{'_linksets_it'} = $self->generate_iterator('linksets')
        if (!exists $self->{'_linksets_it'});
    $self->{'_linksets_it'}->();
}

=head2 get_LinkSets

 Title    : get_LinkSets
 Usage    : 
 Function : 
 Returns  : 
 Args     : 

=cut

# add support for retrieval of data if lazy parsing is enacted

sub get_LinkSets {
    my $self = shift;
    if ($self->is_lazy) {
        $self->warn('get_LinkSets() not implemented when using lazy mode');
        return ();
    }
    $self->parse_data unless $self->data_parsed;
    return ref $self->{'_linksets'} ? @{ $self->{'_linksets'} } : return ();
}

=head2 get_linked_databases

 Title    : get_linked_databases
 Usage    : my @dbs = $eutil->get_linked_databases
 Function : returns list of databases linked to in linksets
 Returns  : array of databases
 Args     : none

=cut

sub get_linked_databases {
    my $self = shift;
    if ($self->is_lazy) {
        $self->warn('get_linked_databases() not implemented when using lazy mode');
        return ();
    }
    $self->parse_data unless $self->data_parsed;
    unless (exists $self->{'_db'}) {
        my %temp;
        # make sure unique db is returned
        # do the linksets have a db? (URLs, db checks do not)
        
        push @{$self->{'_db'}}, map {$_->get_dbto}
            grep { $_->get_dbto ? !$temp{$_->get_dbto}++: 0 } $self->get_LinkSets;
    }
    return @{$self->{'_db'}};
}

=head1 Iterator- and callback-related methods

=cut

{
    my %VALID_ITERATORS = (
        'globalqueries' => 'globalqueries',
        'fieldinfo' =>  'fieldinfo',
        'fieldinfos' => 'fieldinfo',
        'linkinfo' =>  'linkinfo',
        'linkinfos' => 'linkinfo',
        'linksets' => 'linksets',
        'docsums' => 'docsums',
        );

=head2 rewind

 Title    : rewind
 Usage    : $esum->rewind()
            $esum->rewind('recursive')
 Function : retrieve a list of DocSum instances
 Returns  : array of Bio::Tools::EUtilities::Summary::DocSum
 Args     : [optional] Scalar; string ('all') to reset all iterators, or string 
            describing the specific main object iterator to reset. The following
            are recognized (case-insensitive):
            
            'all' - rewind all objects and also recursively resets nested object interators
                    (such as LinkSets and DocSums).
            'globalqueries'
            'fieldinfo' or 'fieldinfos'
            'linkinfo' or 'linkinfos'
            'linksets'
            'docsums'
            

=cut

sub rewind {
    my ($self, $arg) = ($_[0], lc $_[1]);
    my $eutil = $self->eutil;
    if ($self->is_lazy) {
        $self->warn('rewind() not implemented yet when running in lazy mode');
        return;
    }
    $arg ||= 'all';
    if (exists $VALID_ITERATORS{$arg}) {
        delete $self->{'_'.$arg.'_it'};
    } elsif ($arg eq 'all') {
        for my $it (values %VALID_ITERATORS){
            delete $self->{'_'.$it.'_it'} if
                exists $self->{'_'.$it.'_it'};
            map {$_->rewind('all')} $self->get_LinkSets;
            map {$_->rewind('all')} $self->get_DocSums;
        }
    }
}

=head2 generate_iterator

 Title    : generate_iterator
 Usage    : my $coderef = $esum->generate_iterator('linkinfo')
 Function : generates an iterator (code reference) which iterates through
            the relevant object indicated by the args
 Returns  : code reference
 Args     : [REQUIRED] Scalar; string describing the specific object to iterate.
            The following are currently recognized (case-insensitive):
            
            'globalqueries'
            'fieldinfo' or 'fieldinfos'
            'linkinfo' or 'linkinfos'
            'linksets'
            'docsums'
            
            A second argument can also be passed to generate a 'lazy' iterator,
            which loops through and returns objects as they are created (instead
            of creating all data instances up front, then iterating through,
            which is the default). Use of these iterators precludes use of
            rewind() for the time being as we can't guarantee you can rewind(),
            as this depends on whether the data source is seek()able and thus
            'rewindable'. We will add rewind() support at a later time which
            will work for 'seekable' data.
            
            A callback specified using callback() will be used to filter objects
            for any generated iterator. This behaviour is implemented for both
            normal and lazy iterator types and is the default. If you don't want
            this, make sure to reset any previously set callbacks via
            reset_callback() (which just deletes the code ref).
            
=cut

sub generate_iterator {
    my ($self, $obj) = @_;
    if (!$obj) {
        $self->throw('Must provide object type to iterate');
    } elsif (!exists $VALID_ITERATORS{$obj}) {
        $self->throw("Unknown object type [$obj]");
    }
    my $cb = $self->callback;
    if ($self->is_lazy) {
        return sub {
            while (my $obj = $self->parse_chunk) {
                if ($cb) {
                    ($cb->($obj)) ? return $obj : next;
                } else {
                    return $obj;
                }
            }
        }
    } else {
        my $loc = '_'.$VALID_ITERATORS{$obj};
        my $index = $#{$self->{$loc}};
        my $current = 0;
        return sub {
            while ($current <= $index) {
                if ($cb) {
                    ($cb->($self->{$loc}->[$current])) ?
                    return $self->{$loc}->[$current++] : $current ++ && next;
                } else {
                    return $self->{$loc}->[$current++]
                }
            }
        }
    }
}

}

=head2 callback

 Title    : callback
 Usage    : $parser->callback(sub {$_[0]->get_database eq 'protein'});
 Function : Get/set callback code ref used to filter returned data objects
 Returns  : code ref if previously set
 Args     : single argument:
            code ref - evaluates a passed object and returns true or false value
                       (used in iterators)
            'reset' - string, resets the iterator.
            returns upon any other args
=cut

sub callback {
    my ($self, $cb) = @_;
    if ($cb) {
        delete $self->{'_cb'} if ($cb eq 'reset');
        return if ref $cb ne 'CODE';
        $self->{'_cb'} = $cb;
    }
    return $self->{'_cb'};
}

# Private methods

# fixes odd bad XML issue espell data (still present 6-24-07)

sub _seekable {
    return shift->{'_seekable'}
}

sub _fix_espell {
    my ($self, $response) = @_;
    my $temp;
    my $type = ref($response);
    if ($type eq 'GLOB') {
        $temp .= $_ for <$response>;
    } elsif ($type eq 'HTTP::Response') {
        $temp = $response->content;
    } else {
        $self->throw("Unrecognized ref type $type");
    }
    if ($temp =~ m{^<html>}) {
        $self->throw("NCBI espell nonrecoverable error: HTML content returned")
    }
    $temp =~ s{<ERROR>(.*?)<ERROR>}{<ERROR>$1</ERROR>};
    return $temp;
}

sub _load_eutil_module {
    my ($self, $class) = @_;
    my $ok;
    my $module = "Bio::Tools::EUtilities::" . $class;

    eval {
        $ok = $self->_load_module($module);
    };
    if ( $@ ) {
        print STDERR <<END;
$self: data module $module cannot be found
Exception $@
For more information about the EUtilities system please see the EUtilities docs. 
END
       ;
    }
    return $ok;
}

1;
