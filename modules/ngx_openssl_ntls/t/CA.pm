package CA;

# Copyright (C) Chenglong Zhang (K1)
# Copyright (C) 2021 Alibaba Group Holding Limited

# Sign certs for NTLS test cases.

###############################################################################

use warnings;
use strict;

use base qw/ Exporter /;

our @EXPORT = qw/ make_sm2_ca_subca_end_certs  make_sm2_end_certs
    make_rsa_end_cert make_ec_end_cert /;

our $openssl = $ENV{'TEST_OPENSSL_BINARY'} || '/opt/babassl/bin/openssl';

sub make_sm2_subca($$) {
    my ($t, $tag) = @_;
    my $d = $t->testdir();
    my $ca = "$tag" . "_ca";
    my $subca = "$tag" . "_subca";
    my $ca_cnf = "$tag" . "_ca.cnf";
    my $subca_cnf = "$tag" . "_subca.cnf";

    $t->write_file($subca_cnf, <<EOF);
[ ca ]
default_ca = mysubca

[ mysubca ]
new_certs_dir = $d/$subca/newcerts
database = $d/$subca/certindex
serial = $d/$subca/certserial
default_days = 3
unique_subject = no

# The root key and root certificate.
private_key = $d/$subca/subca.key
certificate = $d/$subca/subca.crt

default_md = sha256

policy = myca_policy

[ myca_policy ]
commonName = supplied

[ sign_req ]
# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature

[ enc_req ]
# Extensions to add to a certificate request
basicConstraints = CA:FALSE
keyUsage = keyAgreement, keyEncipherment, dataEncipherment

[ req ]
default_bits = 1024
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]

EOF

    mkdir("$d/$subca");
    mkdir("$d/$subca/newcerts");
    $t->write_file("$subca/certserial", '1000');
    $t->write_file("$subca/certindex", '');

    # sm2 subca
    system("$openssl ecparam -genkey -name SM2 "
        . "-out $d/$subca.key "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create subca key: $!\n";

    system("$openssl req -config $d/$ca_cnf "
        . "-new -key $d/$subca.key "
        . "-out $d/$subca.csr "
        . "-sm3 -nodes -sigopt sm2_id:1234567812345678 "
        . "-subj /CN=${tag}_sub_ca "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create subca csr: $!\n";

    system("$openssl ca -batch "
        . "-config $d/$ca_cnf "
        . "-in $d/$subca.csr "
        . "-cert $d/$ca.crt -keyfile $d/$ca.key "
        . "-extensions v3_intermediate_ca -notext "
        . "-md sm3 "
        . "-out $d/$subca.crt "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create subca crt: $!\n";
}

sub make_sm2_ca($$) {
    my ($t, $tag) = @_;
    my $d = $t->testdir();
    my $ca = "$tag" . "_ca";
    my $ca_cnf = "$tag" . "_ca.cnf";

    $t->write_file($ca_cnf, <<EOF);
[ ca ]
default_ca = myca

[ myca ]
new_certs_dir = $d/$ca/newcerts
database = $d/$ca/certindex
serial = $d/$ca/certserial
default_days = 3

# The root key and root certificate.
private_key = $d/$ca/ca.key
certificate = $d/$ca/ca.crt

default_md = sha256

policy = myca_policy

[ myca_policy ]
commonName = supplied

[ v3_ca ]
# Extensions for a typical CA (`man x509v3_config`).
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
# Extensions for a typical intermediate CA (`man x509v3_config`).
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ req ]
default_bits = 1024
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

    mkdir("$d/$ca");
    mkdir("$d/$ca/newcerts");
    $t->write_file("$ca/certserial", '1000');
    $t->write_file("$ca/certindex", '');

    # sm2 ca
    system("$openssl ecparam -genkey -name SM2 "
        . "-out $d/$ca.key "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ca key: $!\n";

    system("$openssl req -config $d/$ca_cnf "
        . "-new -key $d/$ca.key "
        . "-out $d/$ca.csr "
        . "-sm3 -nodes -sigopt sm2_id:1234567812345678 "
        . "-subj /CN=${tag}_root_ca "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ca csr: $!\n";

    system("$openssl ca -batch -selfsign "
        . "-config $d/$ca_cnf "
        . "-in $d/$ca.csr -keyfile $d/$ca.key "
        . "-extensions v3_ca -notext "
        . "-md sm3 "
        . "-out $d/$ca.crt "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ca crt: $!\n";
}

sub make_sm2_double_certs($$) {
    my ($t, $tag) = @_;
    my $d = $t->testdir();
    my $subca_cnf = $tag . "_subca.cnf";
    my $subca = $tag . "_subca";


    # sm2 double certs
    system("$openssl ecparam -name SM2 "
        . "-out $d/${tag}_sm2.param "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ${tag} param: $!\n";

    system("$openssl req -config $d/$subca_cnf "
        . "-newkey ec:$d/${tag}_sm2.param "
        . "-nodes -keyout $d/${tag}_sign.key "
        . "-sm3 -sigopt sm2_id:1234567812345678 "
        . "-new -out $d/${tag}_sign.csr "
        . "-subj /CN=${tag}_sign "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ${tag} sign csr: $!\n";

    system("$openssl ca -batch -config $d/$subca_cnf "
        . "-extensions sign_req "
        . "-in $d/${tag}_sign.csr "
        . "-notext -out $d/${tag}_sign.crt "
        . "-cert $d/$subca.crt -keyfile $d/$subca.key "
        . "-md sm3 "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ${tag} sign crt $!\n";

    system("$openssl ca -batch -config $d/$subca_cnf "
        . "-extensions sign_req "
        . "-startdate 20000101000000Z -enddate 20010101000000Z "
        . "-in $d/${tag}_sign.csr "
        . "-notext -out $d/${tag}_sign_expire.crt "
        . "-cert $d/$subca.crt -keyfile $d/$subca.key "
        . "-md sm3 "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ${tag} sign expire crt $!\n";

    system("$openssl req -config $d/$subca_cnf "
        . "-newkey ec:$d/${tag}_sm2.param "
        . "-nodes -keyout $d/${tag}_enc.key "
        . "-sm3 -sigopt sm2_id:1234567812345678 "
        . "-new -out $d/${tag}_enc.csr "
        . "-subj /CN=${tag}_enc "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ${tag} enc csr: $!\n";

    system("$openssl ca -batch -config $d/$subca_cnf "
        . "-extensions enc_req "
        . "-in $d/${tag}_enc.csr "
        . "-notext -out $d/${tag}_enc.crt "
        . "-cert $d/$subca.crt -keyfile $d/$subca.key "
        . "-md sm3 "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ${tag} enc crt $!\n";

    system("$openssl ca -batch -config $d/$subca_cnf "
        . "-extensions enc_req "
        . "-startdate 20000101000000Z -enddate 20010101000000Z "
        . "-in $d/${tag}_enc.csr "
        . "-notext -out $d/${tag}_enc_expire.crt "
        . "-cert $d/$subca.crt -keyfile $d/$subca.key "
        . "-md sm3 "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create ${tag} enc expire crt $!\n";

}

sub make_sm2_end_certs($$) {
    my ($t, $tag) = @_;
    my $d = $t->testdir();

    $t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

    foreach my $name ('sign', 'enc') {
        system("$openssl ecparam -genkey -name SM2 -out $d/${tag}_$name.key "
            . ">>$d/openssl.out 2>&1") == 0 or die "Can't create key: $!\n";

        system("$openssl req -x509 -new -key $d/${tag}_$name.key "
            . "-config $d/openssl.conf -subj /CN=${tag}_$name/ "
            . "-out $d/${tag}_$name.crt -keyout $d/${tag}_$name.key "
            . ">>$d/openssl.out 2>&1") == 0
            or die "Can't create certificate for ${tag}_$name: $!\n";
    }

    $t->write_file("${tag}_sign_enc.crt",
        $t->read_file("${tag}_sign.crt")
            . $t->read_file("${tag}_enc.crt"));
}

sub make_sm2_ca_subca_end_certs($$) {
    my ($t, $tag) = @_;

    make_sm2_ca($t, $tag);
    make_sm2_subca($t, $tag);
    make_sm2_double_certs($t, $tag);

    $t->write_file("${tag}_ca_chain.crt",
        $t->read_file("${tag}_subca.crt")
            . $t->read_file("${tag}_ca.crt"));

    $t->write_file("${tag}_sign_enc.crt",
        $t->read_file("${tag}_sign.crt")
            . $t->read_file("${tag}_enc.crt"));

}

sub make_rsa_end_cert($) {
    my ($t) = @_;
    my $d = $t->testdir();

    $t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

    system("$openssl genrsa -out $d/rsa.key 1024 "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create RSA pem: $!\n";

    system("$openssl req -x509 -new -key $d/rsa.key "
        . "-config $d/openssl.conf -subj /CN=rsa/ "
        . "-out $d/rsa.crt -keyout $d/rsa.key "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create certificate for rsa: $!\n";
}

sub make_ec_end_cert($) {
    my ($t) = @_;
    my $d = $t->testdir();

    $t->write_file('openssl.conf', <<EOF);
[ req ]
default_bits = 1024
encrypt_key = no
distinguished_name = req_distinguished_name
[ req_distinguished_name ]
EOF

    system("$openssl ecparam -genkey -out $d/ec.key -name prime256v1 "
        . ">>$d/openssl.out 2>&1") == 0 or die "Can't create EC pem: $!\n";

    system("$openssl req -x509 -new -key $d/ec.key "
        . "-config $d/openssl.conf -subj /CN=ec/ "
        . "-out $d/ec.crt -keyout $d/ec.key "
        . ">>$d/openssl.out 2>&1") == 0
        or die "Can't create certificate for ec: $!\n";
}
###############################################################################

1;

###############################################################################