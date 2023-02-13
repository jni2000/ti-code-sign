#!/bin/bash
#
# Script to add x509 certificate to binary for K3 bootloaders
#
# Copyright (C) 2022-2023 Texas Instruments Incorporated - http://www.ti.com/
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
#
#   Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in the
#   documentation and/or other materials provided with the
#   distribution.
#
#   Neither the name of Texas Instruments Incorporated nor the names of
#   its contributors may be used to endorse or promote products derived
#   from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# Variables
VALID_SHAS="sha256 sha384 sha512 sha224"
PREFIX=$(dirname $0)/..
BUILD_DIR=${O:- .}
OUTPUT=$BUILD_DIR/x509-firmware.bin
TEMP_X509=$BUILD_DIR/x509-temp.cert
CERT=$BUILD_DIR/certificate.bin
VALID_ROM_CORES="public secure"
SHA=sha512
CORE=secure
SW_REV=0
LOADADDR=0x00040000
COMBINED=false

declare -A sha_oids
sha_oids["sha256"]=2.16.840.1.101.3.4.2.1
sha_oids["sha384"]=2.16.840.1.101.3.4.2.2
sha_oids["sha512"]=2.16.840.1.101.3.4.2.3
sha_oids["sha224"]=2.16.840.1.101.3.4.2.4

declare -A options_help
options_help[q]="Flag must be set if device follows combined boot flow"
options_help[b]="Boot Loader:Bin file corresponding to boot loader on R5"
options_help[l]="SBL loadaddress: R5 Bootloader load address"
options_help[s]="SYSFW: Bin file corresponding to sysfw image"
options_help[m]="SYSFW loadaddress: SYSFW image load address"
options_help[d]="SYSFW_DATA: Bin file corresponding to combined board configurations"
options_help[n]="SYSFW_DATA loadaddr: Combine board configuration load address"
options_help[t]="DM_DATA: Bin file corresponding to combined board configurations for RM and PM. If this is used, RM and PM do not need to be provided as part of SYSFW_DATA. (OPTIONAL)"
options_help[y]="DM_DATA loadaddr: Combine RM and PM blob board configuration load address (OPTIONAL)"
options_help[k]="key_file:file with key inside it. If not provided script generates a degenerate key."
options_help[r]="sw-rev: Software Revision other than 0. If not provided defaults to 0."
options_help[c]="SYSFW CERT: SYSFW Inner Certificate"
options_help[o]="output_file:Name of the final output file. default x509-firmware.bin"
options_help[w]="sha_type:sha type to be used for certificate generation. Default is sha512. Valid option are $VALID_SHAS"
options_help[u]=":Countersign firmware image. This signs a previously signed image for a second time."
options_help[a]="core:target core on which the image would be running. Default is secure. Valid option for rom are $VALID_ROM_CORES."

display_usage() {
	if [ -n "$*" ]; then
		echo "ERROR: $*"
	fi
	echo -n "Usage: $0 "
	for option in "${!options_help[@]}"
	do
		arg=`echo ${options_help[$option]}|cut -d ':' -f1`
		if [ -n "$arg" ]; then
			arg=" $arg"
		fi
		echo -n "[-$option$arg] "
	done
	echo
	echo -e "\nWhere:"
	for option in "${!options_help[@]}"
	do
		arg=`echo ${options_help[$option]}|cut -d ':' -f1`
		txt=`echo ${options_help[$option]}|cut -d ':' -f2`
		tb="\t\t\t"
		if [ -n "$arg" ]; then
			arg=" $arg"
			tb="\t"
		fi
		echo -e "   -$option$arg:$tb$txt"
	done
	echo
	echo "Examples of usage:-"
	echo "# Example of generation a combined boot image"
	echo "    $0 -b u-boot-spl.bin -l 0x41c00000 -s ti-sci-firmware-j7200-gp-vlab.bin -m 0x40000 -d combined-cfg.bin -n 0x7f000 -o tiboot3.bin"
	echo
	echo "# Example of generation of a split boardcfg image for use with DM firmware"
	echo "    $0 -b u-boot-spl.bin -l 0x41c00000 -s ti-fs-firmware-j7200-gp.bin -m 0x40000 -d combined-tifs-cfg.bin -n 0x7f000 -t out/soc/j7200/evm/combined-dm-cfg.bin -y 0x41c80000 -k ti-degenerate-key.pem -o tiboot3.bin"
	echo
	echo "# Generate x509 certificate with degenerate key from bin"
	echo "    $0 -b ti-sci-firmware-am6x.bin -o out.bin -l 0x40000"
}

arg_parser() {
	while getopts ":b:l:s:m:d:n:k:o:h:t:y:r:c:p:w:ua:q" opt
	do
		case $opt in
		q)
			COMBINED=true
		;;
		b)
			SBL=$OPTARG
			BIN=$OPTARG
		;;
		l)
			SBL_LOADADDR=$OPTARG
			LOADADDR=$OPTARG
		;;
		s)
			SYSFW=$OPTARG
		;;
		m)
			SYSFW_LOADADDR=$OPTARG
		;;
		d)
			SYSFW_DATA=$OPTARG
		;;
		n)
			SYSFW_DATA_LOADADDR=$OPTARG
		;;
		t)
			DM_DATA=$OPTARG
		;;
		y)
			DM_DATA_LOADADDR=$OPTARG
		;;
		k)
			KEY=$OPTARG
		;;
		o)
			OUTPUT=$OPTARG
		;;
		r)
			SW_REV=$OPTARG
		;;
		c)
			SYSFW_INNER_CERT=$OPTARG
		;;
		w)
			SHA=$OPTARG
		;;
		u)
			CERTTYPE=3	# CERT_TYPE_FIRMWARE_COUNTERSIGN
		;;
		a)
			CORE=$OPTARG
		;;
		h)
			display_usage
			exit 0
		;;
		\?)
			display_usage "Invalid Option '-$OPTARG'"
			exit 1
		;;
		:)
			display_usage "Option '-$OPTARG' Needs an argument."
			exit 1
		;;
		esac
	done
}

# Validate arguments
arg_validate() {
	# Check whether SHA passed is valid
	sha_valid=0
	for tsha in $VALID_SHAS
	do
		if [ "$tsha" == "$SHA" ]; then
			sha_valid=1
		fi
	done
	if [ $sha_valid == 0 ]; then
		display_usage "Invalid sha input $SHA"
		exit 1
	fi
	# Make sure SBL or BIN is passed
	if [ -z ${SBL} ] && [ -z ${BIN} ]
	then
		display_usage "missing parameter SPL or BIN"
		exit 1
	fi

	# Check where this tool is installed
	TEMP_DIR=${PREFIX}/templates
	if [ ! -d ${TEMP_DIR} ]
	then
		TEMP_DIR=${TI_SECURE_DEV_PKG}/templates
		if [ ! -f ${TEMP_DIR} ]
		then
			display_usage "Template directory cannot be found, correctly define TI_SECURE_DEV_PKG environment variable"
			exit 1
		fi
	fi

	# check where this tool is installed
	if [ -z ${KEY} ]; then
		KEY=${PREFIX}/keys/ti-degenerate-key.pem
		if [ ! -f ${KEY} ]; then
			KEY=${TI_SECURE_DEV_PKG}/keys/ti-degenerate-key.pem
			if [ ! -f ${KEY} ]; then
				fn_display_usage "No key is provided and degenerate key not found, correctly define TI_SECURE_DEV_PKG environment variable"
			fi
			PREFIX=${TI_SECURE_DEV_PKG}
		fi
	fi
}

# Setup parameters for non-combined boot flow
prep_single() {

	VALID_CORES=$VALID_ROM_CORES

	# Verify for valid core inputs
	core_valid=0
	for tcore in $VALID_CORES
	do
		if [ "$tcore" == "$CORE" ]; then
			core_valid=1
		fi
	done
	if [ $core_valid == 0 ]; then
		display_usage "Invalid target core $CORE"
		exit 1
	fi
	if [ "$CORE" == "secure" ]; then
		if [ -z "$CERTTYPE" ]; then
			CERTTYPE=2	# CERT_TYPE_FIRMWARE_IMAGE_BIN
		fi
		BOOTCORE=0		# Secure
		BOOTCORE_OPTS=32
	else
		CERTTYPE=1		# CERT_TYPE_PRIMARY_IMAGE_BIN
		BOOTCORE=16		# Public
		if [ "${COMBINED}" == true ]; then
			BOOTCORE_OPTS=32
		else
			BOOTCORE_OPTS=0
		fi
	fi

	SHA_OID=${sha_oids["$SHA"]}
	SHA_VAL=`openssl dgst -$SHA -hex $BIN | sed -e "s/^.*= //g"`
	BIN_SIZE=`cat $BIN | wc -c`
	ADDR=`printf "%08x" $LOADADDR`
}

# Setup parameters for combined boot flow
prep_combined() {
	SHA_OID=${sha_oids["$SHA"]}

	SBL_SHA_VAL=`openssl dgst -$SHA -hex $SBL | sed -e "s/^.*= //g"`
	SBL_SIZE=`cat $SBL | wc -c`
	SBL_ADDR=`printf "%08x" $SBL_LOADADDR`

	SYSFW_SHA_VAL=`openssl dgst -$SHA -hex $SYSFW | sed -e "s/^.*= //g"`
	SYSFW_SIZE=`cat $SYSFW | wc -c`
	SYSFW_ADDR=`printf "%08x" $SYSFW_LOADADDR`

	SYSFW_DATA_SHA_VAL=`openssl dgst -$SHA -hex $SYSFW_DATA | sed -e "s/^.*= //g"`
	SYSFW_DATA_SIZE=`cat $SYSFW_DATA | wc -c`
	SYSFW_DATA_ADDR=`printf "%08x" $SYSFW_DATA_LOADADDR`

	NUM_COMPS_COUNT=3

        # Only process Inner Certificate if this variable is provided, or set size to 0 and num_comps to 3 for cert
    if [ -n "$SYSFW_INNER_CERT" ]; then
        SYSFW_INNER_CERT_SHA_VAL=`openssl dgst -$SHA -hex $SYSFW_INNER_CERT | sed -e "s/^.*= //g"`
        SYSFW_INNER_CERT_SIZE=`cat $SYSFW_INNER_CERT | wc -c`
        NUM_COMPS_COUNT=$(expr $NUM_COMPS_COUNT + 1)
        SYSFW_INNER_CERT_EXT_BOOT_SEQUENCE_STRING="sysfw_inner_cert=SEQUENCE:sysfw_inner_cert"
	    read -r -d '' SYSFW_INNER_CERT_EXT_BOOT_BLOCK << EOM
\\
 [sysfw_inner_cert]\\
 compType = INTEGER:3\\
 bootCore = INTEGER:0\\
 compOpts = INTEGER:0\\
 destAddr = FORMAT:HEX,OCT:00000000\\
 compSize = INTEGER:SYSFW_INNER_CERT_IMAGE_SIZE\\
 shaType  = OID:SYSFW_INNER_CERT_SHA_OID\\
 shaValue = FORMAT:HEX,OCT:SYSFW_INNER_CERT_SHA_VAL
EOM
	else
		SYSFW_INNER_CERT_SIZE=`printf "%08x" 0`
		SYSFW_INNER_CERT_EXT_BOOT_SEQUENCE_STRING=""
		SYSFW_INNER_CERT_EXT_BOOT_BLOCK=""
	fi

	# Only process DM_DATA is variable is provided, or set size to 0 and num_comps to 3 for cert
	if [ -n "$DM_DATA" ]; then
		DM_DATA_SHA_VAL=`openssl dgst -$SHA -hex $DM_DATA | sed -e "s/^.*= //g"`
		DM_DATA_SIZE=`cat $DM_DATA | wc -c`
		DM_DATA_ADDR=`printf "%08x" $DM_DATA_LOADADDR`
		NUM_COMPS_COUNT=$(expr $NUM_COMPS_COUNT + 1)
		DM_DATA_EXT_BOOT_SEQUENCE_STRING="dm_data=SEQUENCE:dm_data"
	read -r -d '' DM_DATA_EXT_BOOT_BLOCK << EOM
\\
 [dm_data]\\
 compType = INTEGER:17\\
 bootCore = INTEGER:16\\
 compOpts = INTEGER:0\\
 destAddr = FORMAT:HEX,OCT:DM_DATA_DEST_ADDR\\
 compSize = INTEGER:DM_DATA_IMAGE_SIZE\\
 shaType  = OID:DM_DATA_IMAGE_SHA_OID\\
 shaValue = FORMAT:HEX,OCT:DM_DATA_IMAGE_SHA_VAL
EOM
	else
		DM_DATA_SIZE=`printf "%08x" 0`
		DM_DATA_EXT_BOOT_SEQUENCE_STRING=""
		DM_DATA_EXT_BOOT_BLOCK=""
	fi

	TOTAL_SIZE=$(expr $SBL_SIZE + $SYSFW_SIZE + $SYSFW_DATA_SIZE + $SYSFW_INNER_CERT_SIZE + $DM_DATA_SIZE)
}

# Generate x509 Template for combined boot flow
gen_template_combined() {
	X509_COMBINED_TEMPLATE_TXT=$(mktemp) || exit 1
	cat ${PREFIX}/templates/x509-rom-combined-template.txt > ${X509_COMBINED_TEMPLATE_TXT}
}

# Generate x509 Template for non-combined flow
gen_template() {
	X509_TEMPLATE_TXT=$(mktemp) || exit 1
	cat ${PREFIX}/templates/x509-rom-template.txt > ${X509_TEMPLATE_TXT}
}

# Generate x509 certificate for combined flow
gen_cert_combined() {
	sed -i "s/SYSFW_INNER_CERT_EXT_BOOT_BLOCK/$SYSFW_INNER_CERT_EXT_BOOT_BLOCK/" ${X509_COMBINED_TEMPLATE_TXT}
	sed -i "s/DM_DATA_EXT_BOOT_BLOCK/$DM_DATA_EXT_BOOT_BLOCK/" ${X509_COMBINED_TEMPLATE_TXT}
	echo "Combined boot flow certificate being generated..."
	sed -e "s/SW_REV/$SW_REV/" \
	    -e "s/NUM_COMPS_COUNT/$NUM_COMPS_COUNT/" \
		-e "s/SBL_DEST_ADDR/$SBL_ADDR/" \
		-e "s/SBL_IMAGE_SIZE/$SBL_SIZE/" \
	    -e "s/SBL_IMAGE_SHA_OID/$SHA_OID/" \
	    -e "s/SBL_IMAGE_SHA_VAL/$SBL_SHA_VAL/" \
	    -e "s/SYSFW_DEST_ADDR/$SYSFW_ADDR/" \
	    -e "s/SYSFW_IMAGE_SIZE/$SYSFW_SIZE/" \
	    -e "s/SYSFW_IMAGE_SHA_OID/$SHA_OID/" \
	    -e "s/SYSFW_IMAGE_SHA_VAL/$SYSFW_SHA_VAL/" \
	    -e "s/SYSFW_DATA_DEST_ADDR/$SYSFW_DATA_ADDR/" \
	    -e "s/SYSFW_DATA_IMAGE_SIZE/$SYSFW_DATA_SIZE/" \
	    -e "s/SYSFW_DATA_IMAGE_SHA_OID/$SHA_OID/" \
	    -e "s/SYSFW_DATA_IMAGE_SHA_VAL/$SYSFW_DATA_SHA_VAL/" \
	    -e "s/SYSFW_INNER_CERT_EXT_BOOT_SEQUENCE_STRING/$SYSFW_INNER_CERT_EXT_BOOT_SEQUENCE_STRING/" \
	    -e "s/SYSFW_INNER_CERT_DEST_ADDR/$SYSFW_INNER_CERT_ADDR/" \
	    -e "s/SYSFW_INNER_CERT_IMAGE_SIZE/$SYSFW_INNER_CERT_SIZE/" \
	    -e "s/SYSFW_INNER_CERT_SHA_OID/$SHA_OID/" \
	    -e "s/SYSFW_INNER_CERT_SHA_VAL/$SYSFW_INNER_CERT_SHA_VAL/" \
	    -e "s/DM_DATA_EXT_BOOT_BLOCK/$DM_DATA_EXT_BOOT_BLOCK/" \
	    -e "s/DM_DATA_EXT_BOOT_SEQUENCE_STRING/$DM_DATA_EXT_BOOT_SEQUENCE_STRING/" \
	    -e "s/DM_DATA_DEST_ADDR/$DM_DATA_ADDR/" \
	    -e "s/DM_DATA_IMAGE_SIZE/$DM_DATA_SIZE/" \
	    -e "s/DM_DATA_IMAGE_SHA_OID/$SHA_OID/" \
	    -e "s/DM_DATA_IMAGE_SHA_VAL/$DM_DATA_SHA_VAL/" \
	    -e "s/TOTAL_IMAGE_LENGTH/$TOTAL_SIZE/" ${X509_COMBINED_TEMPLATE_TXT} > $TEMP_X509
	openssl req -new -x509 -key $KEY -nodes -outform DER -out $CERT -config ${TEMP_X509} -$SHA
}

# Generate x509 certificate for non-combined flow
gen_cert() {
	echo "Certificate being generated..."
	sed -e "s/TEST_IMAGE_LENGTH/$BIN_SIZE/"	\
		-e "s/TEST_IMAGE_SHA_OID/$SHA_OID/" \
		-e "s/TEST_IMAGE_SHA_VAL/$SHA_VAL/" \
		-e "s/TEST_CERT_TYPE/$CERTTYPE/" \
		-e "s/TEST_BOOT_CORE_OPTS/$BOOTCORE_OPTS/" \
		-e "s/TEST_BOOT_CORE/$BOOTCORE/" \
		-e "s/TEST_SWRV/$SW_REV/" \
		-e "s/TEST_BOOT_ADDR/$ADDR/" ${X509_TEMPLATE_TXT} > $TEMP_X509
	openssl req -new -x509 -key $KEY -nodes -outform DER -out $CERT -config $TEMP_X509 -$SHA
}

# Main function for combined boot flow
combined() {
	prep_combined
	gen_template_combined
	gen_cert_combined
	cat $CERT $SBL $SYSFW $SYSFW_DATA $SYSFW_INNER_CERT $DM_DATA > $OUTPUT

	echo "SUCCESS: Image $OUTPUT generated."
	# Remove all intermediate files
	rm ${X509_COMBINED_TEMPLATE_TXT} $CERT $TEMP_X509
}

# Main function for non-combined boot flow
non-combined() {
	prep_single
	gen_template
	gen_cert
	cat $CERT $BIN > $OUTPUT

	echo "SUCCESS: Image $OUTPUT generated."

	# Remove all intermediate files
	rm $TEMP_X509 $CERT ${X509_TEMPLATE_TXT}
}

main() {

	# Parse and validate arguments
	arg_parser "$@"
	arg_validate

	# Perform signing based on whether combined/non-combined flow
    if [ "$COMBINED" == true ]; then
        combined
    else
        non-combined
    fi
}

main "$@"