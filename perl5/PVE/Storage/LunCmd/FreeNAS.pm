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

# FreeNAS API Definitions
my $freenas_api_version = "v1.0";
my $freenas_api_methods = undef;
my $freenas_api_variables = undef;
my $freenas_api_version_methods = {
    "v1.0" => {
        "config"       => "/api/v1.0/services/iscsi/globalconfiguration/",
        "target"       => "/api/v1.0/services/iscsi/target/",
        "extent"       => "/api/v1.0/services/iscsi/extent/",
        "targetextent" => "/api/v1.0/services/iscsi/targettoextent/",
    },
    "v2.0" => {
        "config"       => "/api/v2.0/iscsi/global",
        "target"       => "/api/v2.0/iscsi/target/",
        "extent"       => "/api/v2.0/iscsi/extent/",
        "targetextent" => "/api/v2.0/iscsi/targetextent/",
    },
};

#
#
#
my $freenas_api_version_variables = {
    "v1.0" => {
        "basename"   => "iscsi_basename",
        "lunid"      => "iscsi_lunid",
        "extentid"   => "iscsi_extentid",
        "targetid"   => "iscsi_targetid",
        "extentpath" => "iscsi_target_extent_path",
        "extentnaa"  => "iscsi_target_extent_naa",
        "targetname" => "iscsi_target_name",
    },
    "v2.0" => {
        "basename"   => "basename",
        "lunid"      => "lunid",
        "extentid"   => "extent",
        "targetid"   => "target",
        "extentpath" => "path",
        "extentnaa"  => "naa",
        "targetname" => "name",
    },
};

#
#
#
my $freenas_apiv2_parameters = {
    "target" => {
        "none" => undef,
    },
    "extent" => {
        "force" => "true",
    },
    "targetextent" => {
        "remove" => "true",
        "force" => "true",
    },
};

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

    syslog("info",(caller(0))[3] . " : $method(@params)");

    if(!defined($scfg->{'freenas_user'}) || !defined($scfg->{'freenas_password'})) {
        die "Undefined freenas_user and/or freenas_password.";
    }

    freenas_api_check($scfg, $timeout);

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
    if($method eq "list_extent") {
        return run_list_extent($scfg, $timeout, $method, @params);
    }
    if($method eq "list_lu") {
        return run_list_lu($scfg, $timeout, $method, "name", @params);
    }

    syslog("error",(caller(0))[3] . " : unknown method $method");
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

    syslog("info", (caller(0))[3] . " : called");

    shift(@params);
    run_delete_lu($scfg, $timeout, $method, @params);
    return run_create_lu($scfg, $timeout, $method, @params);
}

#
#
#
sub run_list_view {
    my ($scfg, $timeout, $method, @params) = @_;

    syslog("info", (caller(0))[3] . " : called");

    return run_list_lu($scfg, $timeout, $method, "lun-id", @params);
}

#
#
#
sub run_list_lu {
    my ($scfg, $timeout, $method, $result_value_type, @params) = @_;
    my $object = $params[0];
    syslog("info", (caller(0))[3] . " : called with (method=$method; result_value_type=$result_value_type; object=$object)");

    my $adddev    = ($freenas_api_version eq "v2.0") ? "/dev/" : "";
    my $result = undef;
    my $luns = freenas_list_lu($scfg);
    foreach my $lun (@$luns) {
        syslog("info", (caller(0))[3] . " : Verifing '$lun->{$freenas_api_variables->{'extentpath'}}' and '$object'");
        if ($adddev . $lun->{$freenas_api_variables->{'extentpath'}} eq $object) {
            $result = $result_value_type eq "lun-id" ? $lun->{$freenas_api_variables->{'lunid'}} : $adddev . $lun->{$freenas_api_variables->{'extentpath'}};
            syslog("info",(caller(0))[3] . "($object) '$result_value_type' found $result");
            last;
        }
    }
    if(!defined($result)) {
        syslog("info", (caller(0))[3] . "($object) : $result_value_type : lun not found");
    }

    return $result;
}

#
#
#
sub run_list_extent {
    my ($scfg, $timeout, $method, @params) = @_;
    my $object = $params[0];

    syslog("info", (caller(0))[3] . " : called with (method=$method; object=$object)");

    my $adddev    = ($freenas_api_version eq "v2.0") ? "/dev/" : "";
    my $result = undef;
    my $luns = freenas_list_lu($scfg);
    foreach my $lun (@$luns) {
        syslog("info", (caller(0))[3] . " : Verifing '$lun->{$freenas_api_variables->{'extentpath'}}' and '$object'");
        if ($adddev . $lun->{$freenas_api_variables->{'extentpath'}} eq $object) {
            $result = $lun->{$freenas_api_variables->{'extentnaa'}};
            syslog("info","FreeNAS::list_extent($object): naa found $result");
            last;
        }
    }
    if (!defined($result)) {
        syslog("info","FreeNAS::list_extent($object): naa not found");
    }

    return $result;
}

#
#
#
sub run_create_lu {
    my ($scfg, $timeout, $method, @params) = @_;
    my $lun_path  = $params[0];

    syslog("info", (caller(0))[3] . " : called with (method=$method; param[0]=$lun_path)");

    my $lun_id    = freenas_get_first_available_lunid($scfg);

    die "Maximum number of LUNs per target is $MAX_LUNS" if scalar $lun_id >= $MAX_LUNS;
    die "$params[0]: LUN $lun_path exists" if defined(run_list_lu($scfg, $timeout, $method, "name", @params));

    my $target_id = freenas_get_targetid($scfg);
    die "Unable to find the target id for $scfg->{target}" if !defined($target_id);

    # Create the extent
    my $extent = freenas_iscsi_create_extent($scfg, $lun_path);

    # Associate the new extent to the target
    my $link = freenas_iscsi_create_target_to_extent($scfg, $target_id, $extent->{'id'}, $lun_id);

    if (defined($link)) {
       syslog("info","FreeNAS::create_lu(lun_path=$lun_path, lun_id=$lun_id) : successful");
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

    syslog("info", (caller(0))[3] . " : called with (method=$method; param[0]=$lun_path)");

    my $adddev    = ($freenas_api_version eq "v2.0") ? "/dev/" : "";
    my $luns      = freenas_list_lu($scfg);
    my $lun       = undef;
    my $link      = undef;
    foreach my $item (@$luns) {
       if($adddev . $item->{ $freenas_api_variables->{'extentpath'}} eq $lun_path) {
           $lun = $item;
           last;
       }
    }

    die "Unable to find the lun $lun_path for $scfg->{target}" if !defined($lun);

    my $target_id = freenas_get_targetid($scfg);
    die "Unable to find the target id for $scfg->{target}" if !defined($target_id);

    # find the target to extent
    my $target2extents = freenas_iscsi_get_target_to_extent($scfg);

    syslog("info", (caller(0))[3] . " : searching for 'targetextent' with (target_id=$target_id; lun_id=$lun->{$freenas_api_variables->{'lunid'}}; extent_id=$lun->{id})");
    foreach my $item (@$target2extents) {
        if($item->{$freenas_api_variables->{'targetid'}} == $target_id &&
           $item->{$freenas_api_variables->{'lunid'}} == $lun->{$freenas_api_variables->{'lunid'}} &&
           $item->{$freenas_api_variables->{'extentid'}} == $lun->{'id'}) {
            $link = $item;
            syslog("info", (caller(0))[3] . " : found 'targetextent'(target_id=$item->{$freenas_api_variables->{'targetid'}}; lun_id=$item->{$freenas_api_variables->{'lunid'}}; extent_id=$item->{$freenas_api_variables->{'extentid'}})");
            last;
        }
    }
    die "Unable to find the link for the lun $lun_path for $scfg->{target}" if !defined($link);

    # Remove the extent
    my $remove_extent = freenas_iscsi_remove_extent($scfg, $lun->{'id'});

    # Remove the link
    my $remove_link = freenas_iscsi_remove_target_to_extent($scfg, $link->{'id'});

    if($remove_link == 1 && $remove_extent == 1) {
        syslog("info", (caller(0))[3] . "(lun_path=$lun_path) : successful");
    } else {
        die "Unable to delete lun $lun_path";
    }

    return "";
}

#
# Check to see what FreeNAS version we are running and set
# the FreeNAS.pm to use the correct API version of FreeNAS
#
sub freenas_api_check {
    my ($scfg, $timeout) = @_;

    syslog("info", (caller(0))[3] . " : called");

    my $client = undef;
    my $scheme = $scfg->{freenas_use_ssl} ? "https" : "http";
    my $apihost = defined($scfg->{freenas_apiv4_host}) ? $scfg->{freenas_apiv4_host} : $scfg->{portal};
    my $apiping = '/api/v1.0/system/version/';

    $client = REST::Client->new();
    $client->setHost($scheme . '://' . $apihost);
    $client->addHeader('Content-Type', 'application/json');
    $client->addHeader('Authorization', 'Basic ' . encode_base64($scfg->{freenas_user} . ':' . $scfg->{freenas_password}));
    # If using SSL, don't verify SSL certs
    if ($scfg->{freenas_use_ssl}) {
        $client->getUseragent()->ssl_opts(verify_hostname => 0);
        $client->getUseragent()->ssl_opts(SSL_verify_mode => SSL_VERIFY_NONE);
    }
    # Check if the APIs are accessable via the selected host and scheme
    my $code = $client->request('GET', $apiping)->responseCode();
    if ($code != 200) {
        freenas_api_log_error($client, "freenas_api_call");
        die "Unable to connect to the FreeNAS API service at '" . $apihost . "' using the '" . $scheme . "' protocol";
    }
    my $result = decode_json($client->responseContent());
    syslog("info", (caller(0))[3] . " : successful : Server version: " . $result->{'fullversion'});
    $result->{'fullversion'} =~ s/^(\w+)\-(\d+)\.(\d+)\-U(\d+)\.?(\d?)//;
    my $freenas_version = sprintf("%02d%02d%02d%02d", $2, $3, $4, $5);
    syslog("info", (caller(0))[3] . " : ". $1 . " Unformatted Version: " . $freenas_version);
    if ($freenas_version >= 11030100) {
        $freenas_api_version = "v2.0";
    }
    syslog("info", (caller(0))[3] . " : Using " . $1 ." API version " . $freenas_api_version);
    $freenas_api_methods   = $freenas_api_version_methods->{$freenas_api_version};
    $freenas_api_variables = $freenas_api_version_variables->{$freenas_api_version};
}

#
### FREENAS API CALLING ###
#
sub freenas_api_call {
    my ($scfg, $method, $path, $data) = @_;
    my $client = undef;
    my $scheme = $scfg->{freenas_use_ssl} ? "https" : "http";
    my $apihost = defined($scfg->{freenas_apiv4_host}) ? $scfg->{freenas_apiv4_host} : $scfg->{portal};

    $client = REST::Client->new();
    $client->setHost($scheme . '://' . $apihost);
    $client->addHeader('Content-Type'  , 'application/json');
    $client->addHeader('Authorization' , 'Basic ' . encode_base64($scfg->{freenas_user} . ':' . $scfg->{freenas_password}));
    # If using SSL, don't verify SSL certs
    if ($scfg->{freenas_use_ssl}) {
        $client->getUseragent()->ssl_opts(verify_hostname => 0);
        $client->getUseragent()->ssl_opts(SSL_verify_mode => SSL_VERIFY_NONE);
    }
    my $json_data = (defined $data) ? encode_json($data) : undef;
    if ($method eq 'GET') {
        $client->GET($path, $json_data);
    }
    if ($method eq 'DELETE') {
        $client->DELETE($path, $json_data);
    }
    if ($method eq 'POST') {
        $client->POST($path, $json_data);
    }
    syslog("info", (caller(0))[3] . " : successful");

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
    syslog("info", (caller(0))[3] . " : called");
    my $client = freenas_api_call($scfg, 'GET', "$freenas_api_methods->{'config'}", undef);
    my $code = $client->responseCode();

    if ($code == 200) {
        my $result = decode_json($client->responseContent());
        syslog("info", (caller(0))[3] . " : target_basename=" . $result->{$freenas_api_variables->{'basename'}});
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

    syslog("info", (caller(0))[3] . " : called");

    my $client = freenas_api_call($scfg, 'GET', $freenas_api_methods->{'extent'} . "?limit=0", undef);
    my $code = $client->responseCode();
    if ($code == 200) {
        my $result = decode_json($client->responseContent());
        syslog("info", (caller(0))[3] . " : successful");
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
#
sub freenas_iscsi_create_extent {
    my ($scfg, $lun_path) = @_;

    syslog("info", (caller(0))[3] . " : called with (lun_path=$lun_path)");

    my $name = $lun_path;
    $name  =~ s/^.*\///; # all from last /
    $name  = $scfg->{'pool'} . '/' . $name;

    my $device = $lun_path;
    $device =~ s/^\/dev\///; # strip /dev/

    my $request = {
        "v1.0" => {
            "iscsi_target_extent_type"      => "Disk",
            "iscsi_target_extent_name"      => $name,
            "iscsi_target_extent_disk"      => $device,
        },
        "v2.0" => {
            "type"      => "DISK",
            "name"      => $name,
            "disk"      => $device,
        },
    };

    my $client = freenas_api_call($scfg, 'POST', $freenas_api_methods->{'extent'}, $request->{$freenas_api_version});
    my $code = $client->responseCode();
    if ($code == 200 || $code == 201) {
        my $result = decode_json($client->responseContent());
        syslog("info", "FreeNAS::API::create_extent(lun_path=" . $result->{$freenas_api_variables->{'extentpath'}} . ") : successful");
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
    my $request = {
        "v2.0" => {
            "remove" => \1,
            "force"  => \1,
        },
    };

    syslog("info", (caller(0))[3] . " : called with (extent_id=$extent_id)");
    my $client = freenas_api_call($scfg, 'DELETE', $freenas_api_methods->{'extent'} . (($freenas_api_version eq "v2.0") ? "id/" : "") . "$extent_id/", $request->{$freenas_api_version});
    my $code = $client->responseCode();
    if ($code == 200 || $code == 204) {
        syslog("info", (caller(0))[3] . "(extent_id=$extent_id) : successful");
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

    syslog("info", (caller(0))[3] . " : called");

    my $client = freenas_api_call($scfg, 'GET', $freenas_api_methods->{'target'} . "?limit=0", undef);
    my $code = $client->responseCode();
    if ($code == 200) {
        my $result = decode_json($client->responseContent());
        syslog("info", (caller(0))[3] . " : successful");
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

    syslog("info", (caller(0))[3] . " : called");

    my $client = freenas_api_call($scfg, 'GET', $freenas_api_methods->{'targetextent'} . "?limit=0", undef);
    my $code = $client->responseCode();
    if ($code == 200) {
        my $result = decode_json($client->responseContent());
        syslog("info", (caller(0))[3] . " : successful");
        # If 'iscsi_lunid' is undef then it is set to 'Auto' in FreeNAS
        # which should be '0' in our eyes.
        # This gave Proxmox 5.x and FreeNAS 11.1 a few issues.
        foreach my $item (@$result) {
            if (!defined($item->{$freenas_api_variables->{'lunid'}})) {
                $item->{$freenas_api_variables->{'lunid'}} = 0;
                syslog("info", (caller(0))[3] . " : change undef iscsi_lunid to 0");
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

    syslog("info", (caller(0))[3] . " : called with (target_id=$target_id, extent_id=$extent_id, lun_id=$lun_id)");

    my $request = {
        "v1.0" => {
            "iscsi_target"  => $target_id,
            "iscsi_extent"  => $extent_id,
            "iscsi_lunid"   => $lun_id,
        },
        "v2.0" => {
            "target"  => $target_id,
            "extent"  => $extent_id,
            "lunid"   => $lun_id,
        },
    };

    my $client = freenas_api_call($scfg, 'POST', $freenas_api_methods->{'targetextent'}, $request->{$freenas_api_version});
    my $code = $client->responseCode();
    if ($code == 200 || $code == 201) {
        my $result = decode_json($client->responseContent());
        syslog("info", (caller(0))[3] . "(target_id=$target_id, extent_id=$extent_id, lun_id=$lun_id) : successful");
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

    syslog("info", (caller(0))[3] . " : called with (link_id=$link_id)");

    if ($freenas_api_version eq "v2.0") {
        syslog("info", (caller(0))[3] . "(link_id=$link_id) : V2.0 API's so NOT Needed...successful");
        return 1;
    }

    my $client = freenas_api_call($scfg, 'DELETE', $freenas_api_methods->{'targetextent'} . (($freenas_api_version eq "v2.0") ? "id/" : "") . "$link_id/", undef);
    my $code = $client->responseCode();
    if ($code == 200 || $code == 204) {
        syslog("info", (caller(0))[3] . "(link_id=$link_id) : successful");
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

    syslog("info", (caller(0))[3] . " : called");

    my $targets   = freenas_iscsi_get_target($scfg);
    my $target_id = freenas_get_targetid($scfg);

    my @luns        = ();
    my $iscsi_lunid = undef;

    if(defined($target_id)) {
        my $target2extents = freenas_iscsi_get_target_to_extent($scfg);
        my $extents        = freenas_iscsi_get_extent($scfg);

        foreach my $item (@$target2extents) {
            if($item->{$freenas_api_variables->{'targetid'}} == $target_id) {
                foreach my $node (@$extents) {
                    if($node->{'id'} == $item->{$freenas_api_variables->{'extentid'}}) {
                        if ($item->{$freenas_api_variables->{'lunid'}} =~ /(\d+)/) {
                            $iscsi_lunid = "$1";
                        } else {
                            syslog("info", (caller(0))[3] . " : iscsi_lunid did not pass tainted testing");
                            next;
                        }
                        $node->{$freenas_api_variables->{'lunid'}} .= $iscsi_lunid;
                        push(@luns , $node);
                    }
                }
            }
        }
    }
    syslog("info", (caller(0))[3] . " : successful");
    return \@luns;
}

#
# Returns the first available "lunid" (in all targets namespaces)
#
sub freenas_get_first_available_lunid {
    my ($scfg) = @_;

    syslog("info", (caller(0))[3] . " : called");

    my $target_id      = freenas_get_targetid($scfg);
    my $target2extents = freenas_iscsi_get_target_to_extent($scfg);
    my @luns           = ();

    foreach my $item (@$target2extents) {
        push(@luns, $item->{$freenas_api_variables->{'lunid'}}) if ($item->{$freenas_api_variables->{'targetid'}} == $target_id);
    }

    my @sorted_luns =  sort {$a <=> $b} @luns;
    my $lun_id      = 0;

    # find the first hole, if not, give the +1 of the last lun
    foreach my $lun (@sorted_luns) {
        last if $lun != $lun_id;
        $lun_id = $lun_id + 1;
    }

    syslog("info", (caller(0))[3] . " : $lun_id");
    return $lun_id;
}

#
# Returns the target id on FreeNas of the currently configured target of this PVE storage
#
sub freenas_get_targetid {
    my ($scfg) = @_;

    syslog("info", (caller(0))[3] . " : called");

    my $global    = freenas_iscsi_get_globalconfiguration($scfg);
    my $targets   = freenas_iscsi_get_target($scfg);
    my $target_id = undef;

    foreach my $target (@$targets) {
        my $iqn = $global->{$freenas_api_variables->{'basename'}} . ':' . $target->{$freenas_api_variables->{'targetname'}};
        if($iqn eq $scfg->{target}) {
            $target_id = $target->{'id'};
            last;
        }
    }
    syslog("info", (caller(0))[3] . " : successful : $target_id");
    return $target_id;
}


1;
