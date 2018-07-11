package PVE::Storage::LunCmd::FreeNAS;

use strict;
use warnings;
use Data::Dumper;
use PVE::SafeSyslog;
use IO::Socket::SSL;

use REST::Client;
use MIME::Base64;
use JSON;

# Max LUNS per target on the iSCSI server
my $MAX_LUNS = 255;

#
#
#
sub get_base {
    return '/dev/zvol';
}

#
#
#
sub run_lun_command {
    my ($scfg, $timeout, $method, @params) = @_;

    # TODO : Move configuration of the storage
    if(!defined($scfg->{'freenas_user'})) {
        $scfg->{'freenas_user'} = 'root';
        $scfg->{'freenas_password'} = '*** password ***';
    }

    syslog("info","FreeNAS::lun_command : $method(@params)");

    if($method eq "create_lu") {
        return run_create_lu($scfg, $timeout, $method, @params);
    }
    if($method eq "delete_lu") {
        return run_delete_lu($scfg, $timeout, $method, @params);
    }
    if($method eq "import_lu") {
        return run_create_lu($scfg, $timeout, $method, @params);
    }
    if($method eq "modify_lu") {
        return run_modify_lu($scfg, $timeout, $method, @params);
    }
    if($method eq "add_view") {
        return run_add_view($scfg, $timeout, $method, @params);
    }
    if($method eq "list_view") {
        return run_list_view($scfg, $timeout, $method, @params);
    }
    if($method eq "list_lu") {
        return run_list_lu($scfg, $timeout, $method, "name", @params);
    }

    syslog("error","FreeNAS::lun_command : unknown method $method");
    return undef;
}

#
#
#
sub run_add_view {
    return '';
}

#
# a modify_lu occur by example on a zvol resize. we just need to destroy and recreate the lun with the same zvol.
# Be careful, the first param is the new size of the zvol, we must shift params
#
sub run_modify_lu {
    my ($scfg, $timeout, $method, @params) = @_;
    shift(@params);
    run_delete_lu($scfg, $timeout, $method, @params);
    return run_create_lu($scfg, $timeout, $method, @params);
}

#
#
#
sub run_list_view {
    my ($scfg, $timeout, $method, @params) = @_;
    return run_list_lu($scfg, $timeout, $method, "lun-id", @params);
}

#
#
#
sub run_list_lu {
    my ($scfg, $timeout, $method, $result_value_type, @params) = @_;
    my $object = $params[0];
    my $result = undef;

    my $luns = freenas_list_lu($scfg);
    foreach my $lun (@$luns) {
        if ($lun->{'iscsi_target_extent_path'} =~ /^$object$/) {
            $result = $result_value_type eq "lun-id" ? $lun->{'iscsi_lunid'} : $lun->{'iscsi_target_extent_path'};
            syslog("info","FreeNAS::list_lu($object):$result_value_type : lun found $result");
            last;
        }
    }
    if(!defined($result)) {
      syslog("info","FreeNAS::list_lu($object):$result_value_type : lun not found");
    }

    return $result;
}

#
#
#
sub run_create_lu {
    my ($scfg, $timeout, $method, @params) = @_;

    my $lun_path  = $params[0];
    my $lun_id    = freenas_get_first_available_lunid($scfg);

    die "Maximum number of LUNs per target is $MAX_LUNS" if scalar $lun_id >= $MAX_LUNS;
    die "$params[0]: LUN $lun_path exists" if defined(run_list_lu($scfg, $timeout, $method, "name", @params));

    my $target_id = freenas_get_targetid($scfg);
    die "Unable to find the target id for $scfg->{target}" if !defined($target_id);

    my $bs=$scfg->{blocksize};
    if (index($bs, "k") >= 0) {
       chop($bs); $bs = $bs * 1024;
       syslog("info","FreeNAS::create_lu(lun_path=$lun_path, lun_id=$lun_id) : blocksize convert $scfg->{blocksize} = $bs");
    } else {
       syslog("info","FreeNAS::create_lu(lun_path=$lun_path, lun_id=$lun_id) : blocksize $bs");
    }

    # Create the extent
    my $extent = freenas_iscsi_create_extent($scfg, $lun_path, $bs);

    # Associate the new extent to the target
    my $link = freenas_iscsi_create_target_to_extent($scfg, $target_id, $extent->{'id'}, $lun_id);

    if (defined($link)) {
       syslog("info","FreeNAS::create_lu(lun_path=$lun_path, lun_id=$lun_id) : sucessfull");
    } else {
       die "Unable to create lun $lun_path";
    }

    return "";
}

#
#
#
sub run_delete_lu {
    my ($scfg, $timeout, $method, @params) = @_;

    my $lun_path  = $params[0];
    my $luns      = freenas_list_lu($scfg);
    my $lun       = undef;
    my $link      = undef;

    foreach my $item (@$luns) {
       if($item->{'iscsi_target_extent_path'} =~ /^$lun_path$/) {
         $lun = $item;
         last;
       }
    }

    die "Unable to find the lun $lun_path for $scfg->{target}" if !defined($lun);

    my $target_id = freenas_get_targetid($scfg);
    die "Unable to find the target id for $scfg->{target}" if !defined($target_id);

    # find the target to extent
    my $target2extents = freenas_iscsi_get_target_to_extent($scfg);

    foreach my $item (@$target2extents) {
        if($item->{'iscsi_target'} == $target_id            &&
           $item->{'iscsi_lunid'}  == $lun->{'iscsi_lunid'} &&
           $item->{'iscsi_extent'} == $lun->{'id'}) {

            $link = $item;
            last;
        }
    }
    die "Unable to find the link for the lun $lun_path for $scfg->{target}" if !defined($link);

    # Remove the link
    my $remove_link = freenas_iscsi_remove_target_to_extent($scfg, $link->{'id'});

    # Remove the extent
    my $remove_extent = freenas_iscsi_remove_extent($scfg, $lun->{'id'});

    if($remove_link == 1 && $remove_extent == 1) {
        syslog("info","FreeNAS::delete_lu(lun_path=$lun_path) : sucessfull");
    } else {
        die "Unable to delete lun $lun_path";
    }

    return "";
}

#
### FREENAS API CALLING ###
#
sub freenas_api_call {
    my ($scfg, $method, $path, $data) = @_;
    my $client = undef;
    my $scheme = 'http';

    $client = REST::Client->new();
    if ($scfg->{freenas_use_ssl}) {
        $scheme = 'https';
    }
    $client->setHost($scheme . '://'.  $scfg->{portal});
    $client->addHeader('Content-Type'  , 'application/json');
    $client->addHeader('Authorization' , 'Basic ' . encode_base64(  $scfg->{freenas_user} . ':' .  $scfg->{freenas_password}));
    # don't verify SSL certs
    $client->getUseragent()->ssl_opts(verify_hostname => 0);
    $client->getUseragent()->ssl_opts(SSL_verify_mode => SSL_VERIFY_NONE );

    if ($method eq 'GET') {
        $client->GET($path);
    }
    if ($method eq 'DELETE') {
        $client->DELETE($path);
    }
    if ($method eq 'POST') {
        $client->POST($path, encode_json($data));
    }

    return $client
}

#
# Writes the Response and Content to SysLog 
#
sub freenas_api_log_error {
    my ($client, $method) = @_;
    syslog("info","[ERROR]FreeNAS::API::" . $method . " : Response code: " . $client->responseCode());
    syslog("info","[ERROR]FreeNAS::API::" . $method . " : Response content: " . $client->responseContent());
    return 1;
}

#
#
#
sub freenas_iscsi_get_globalconfiguration {
    my ($scfg) = @_;
    my $client = freenas_api_call($scfg, 'GET', "/api/v1.0/services/iscsi/globalconfiguration/", undef);
    my $code = $client->responseCode();

    if ($code == 200) {
        my $result = decode_json($client->responseContent());
        syslog("info","FreeNAS::API::get_globalconfig : target_basename=" . $result->{'iscsi_basename'});
        return $result;
    } else {
        freenas_api_log_error($client, "get_globalconfig");
        return undef;
    }
}

#
# Returns a list of all extents.
# http://api.freenas.org/resources/iscsi/index.html#get--api-v1.0-services-iscsi-extent-
#
sub freenas_iscsi_get_extent {
    my ($scfg) = @_;
    my $client = freenas_api_call($scfg, 'GET', "/api/v1.0/services/iscsi/extent/?limit=0", undef);

    my $code = $client->responseCode();
    if ($code == 200) {
      my $result = decode_json($client->responseContent());
      syslog("info","FreeNAS::API::get_extent : sucessfull");
      return $result;
    } else {
      freenas_api_log_error($client, "get_extent");
      return undef;
    }
}

#
# Create an extent on FreeNas
# http://api.freenas.org/resources/iscsi/index.html#create-resource
# Parameters:
#   - target config (scfg)
#   - lun_path
#   - lun_bs
#
sub freenas_iscsi_create_extent {
    my ($scfg, $lun_path, $lun_bs) = @_;

    my $name = $lun_path;
    $name  =~ s/^.*\///; # all from last /
    $name  = $scfg->{'pool'} . '/' . $name;

    my $device = $lun_path;
    $device =~ s/^\/dev\///; # strip /dev/

    my $request = {
        "iscsi_target_extent_type"      => "Disk",
        "iscsi_target_extent_name"      => $name,
        "iscsi_target_extent_blocksize" => $lun_bs,
        "iscsi_target_extent_disk"      => $device,
    };

    my $client = freenas_api_call($scfg, 'POST', "/api/v1.0/services/iscsi/extent/", $request);
    my $code = $client->responseCode();
    if ($code == 201) {
        my $result = decode_json($client->responseContent());
        syslog("info", "FreeNAS::API::create_extent(lun_path=" . $result->{'iscsi_target_extent_path'} . ", lun_bs=$lun_bs) : sucessfull");
        return $result;
    } else {
        freenas_api_log_error($client, "create_extent");
        return undef;
    }
}

#
# Remove an extent by it's id
# http://api.freenas.org/resources/iscsi/index.html#delete-resource
# Parameters:
#    - scfg
#    - extent_id
#
sub freenas_iscsi_remove_extent {
    my ($scfg, $extent_id) = @_;

    my $client = freenas_api_call($scfg, 'DELETE', "/api/v1.0/services/iscsi/extent/$extent_id/", undef);
    my $code = $client->responseCode();
    if ($code == 204) {
        syslog("info","FreeNAS::API::remove_extent(extent_id=$extent_id) : sucessfull");
        return 1;
    } else {
        freenas_api_log_error($client, "remove_extent");
        return 0;
    }
}

#
# Returns a list of all targets
# http://api.freenas.org/resources/iscsi/index.html#get--api-v1.0-services-iscsi-target-
#
sub freenas_iscsi_get_target {
    my ($scfg) = @_;

    my $client = freenas_api_call($scfg, 'GET', "/api/v1.0/services/iscsi/target/?limit=0", undef);
    my $code = $client->responseCode();
    if ($code == 200) {
        my $result = decode_json($client->responseContent());
        syslog("info","FreeNAS::API::get_target() : sucessfull");
        return $result;
    } else {
        freenas_api_log_error($client, "get_target");
        return undef;
    }
}

#
# Returns a list of associated extents to targets
# http://api.freenas.org/resources/iscsi/index.html#get--api-v1.0-services-iscsi-targettoextent-
#
sub freenas_iscsi_get_target_to_extent {
    my ($scfg) = @_;

    my $client = freenas_api_call($scfg, 'GET', "/api/v1.0/services/iscsi/targettoextent/?limit=0", undef);
    my $code = $client->responseCode();
    if ($code == 200) {
        my $result = decode_json($client->responseContent());
        syslog("info","FreeNAS::API::get_target_to_extent() : sucessfull");
        # If 'iscsi_lunid' is undef then it is set to 'Auto' in FreeNAS
        # which should be '0' in our eyes.
        # This gave Proxmox 5.x and FreeNAS 11.1 a few issues.
        foreach my $item (@$result) {
            if (!defined($item->{'iscsi_lunid'})) {
                $item->{'iscsi_lunid'} = 0;
                syslog("info", "FreeNAS::API::get_target_to_extent() : change undef iscsi_lunid to 0");
            }
        }
        return $result;
    } else {
        freenas_api_log_error($client, "get_target_to_extent");
        return undef;
    }
}

#
# Associate a FreeNas extent to a FreeNas Target
# http://api.freenas.org/resources/iscsi/index.html#post--api-v1.0-services-iscsi-targettoextent-
# Parameters:
#   - target config (scfg)
#   - FreeNas Target ID
#   - FreeNas Extent ID
#   - Lun ID
#
sub freenas_iscsi_create_target_to_extent {
    my ($scfg, $target_id, $extent_id, $lun_id) = @_;

    my $request = {
        "iscsi_target"  => $target_id,
        "iscsi_extent"  => $extent_id,
        "iscsi_lunid"   => $lun_id
    };

    my $client = freenas_api_call($scfg, 'POST', "/api/v1.0/services/iscsi/targettoextent/", $request);
    my $code = $client->responseCode();
    if ($code == 201) {
        my $result = decode_json($client->responseContent());
        syslog("info","FreeNAS::API::create_target_to_extent(target_id=$target_id, extent_id=$extent_id, lun_id=$lun_id) : sucessfull");
        return $result;
    } else {
        freenas_api_log_error($client, "create_target_to_extent");
        return undef;
    }
}

#
# Remove a Target to extent by it's id
# http://api.freenas.org/resources/iscsi/index.html#delete--api-v1.0-services-iscsi-targettoextent-(int-id)-
# Parameters:
#    - scfg
#    - link_id
#
sub freenas_iscsi_remove_target_to_extent {
    my ($scfg, $link_id) = @_;

    my $client = freenas_api_call($scfg, 'DELETE', "/api/v1.0/services/iscsi/targettoextent/$link_id/", undef);
    my $code = $client->responseCode();
    if ($code == 204) {
        syslog("info","FreeNAS::API::remove_target_to_extent(link_id=$link_id) : sucessfull");
        return 1;
    } else {
        freenas_api_log_error($client, "remove_target_to_extent");
        return 0;
    }
}

#
# Returns all luns associated to the current target defined by $scfg->{target}
# This method returns an array reference like "freenas_iscsi_get_extent" do
# but with an additionnal hash entry "iscsi_lunid" retrieved from "freenas_iscsi_get_target_to_extent"
#
sub freenas_list_lu {
    my ($scfg) = @_;

    my $targets   = freenas_iscsi_get_target($scfg);
    my $target_id = freenas_get_targetid($scfg);

    my @luns        = ();
    my $iscsi_lunid = undef;

    if(defined($target_id)) {
        my $target2extents = freenas_iscsi_get_target_to_extent($scfg);
        my $extents        = freenas_iscsi_get_extent($scfg);

        foreach my $item (@$target2extents) {
            if($item->{'iscsi_target'} == $target_id) {
                foreach my $node (@$extents) {
                    if($node->{'id'} == $item->{'iscsi_extent'}) {
                        if ($item->{'iscsi_lunid'} =~ /(\d+)/) {
                            $iscsi_lunid = "$1";
                        } else {
                            syslog("info", "FreeNAS::API::freenas_list_lu : iscsi_lunid did not pass tainted testing");
                            next;
                        }
                        $node->{'iscsi_lunid'} .= $iscsi_lunid;
                        push(@luns , $node);
                    }
                }
            }
        }
    }
    syslog("info", "FreeNAS::API::freenas_list_lu : sucessfull");
    return \@luns;
}

#
# Returns the first available "lunid" (in all targets namespaces)
#
sub freenas_get_first_available_lunid {
    my ($scfg) = @_;

    my $target_id      = freenas_get_targetid($scfg);
    my $target2extents = freenas_iscsi_get_target_to_extent($scfg);
    my @luns           = ();

    foreach my $item (@$target2extents) {
        push(@luns, $item->{'iscsi_lunid'}) if ($item->{'iscsi_target'} == $target_id);
    }

    my @sorted_luns =  sort {$a <=> $b} @luns;
    my $lun_id      = 0;

    # find the first hole, if not, give the +1 of the last lun
    foreach my $lun (@sorted_luns) {
  	    last if $lun != $lun_id;
  	    $lun_id = $lun_id + 1;
    }

    syslog("info", "FreeNAS::API::freenas_get_first_available_lunid : return $lun_id");
    return $lun_id;
}

#
# Returns the target id on FreeNas of the currently configured target of this PVE storage
#
sub freenas_get_targetid {
    my ($scfg) = @_;

    my $global    = freenas_iscsi_get_globalconfiguration($scfg);
    my $targets   = freenas_iscsi_get_target($scfg);
    my $target_id = undef;

    foreach my $target (@$targets) {
        my $iqn = $global->{'iscsi_basename'} . ':' . $target->{'iscsi_target_name'};
        if($iqn eq $scfg->{target}) {
            $target_id = $target->{'id'};
            last;
        }
    }

    return $target_id;
}


1;
