#!/bin/bash
RBD_PROVISIONER="openshift-storage.rbd.csi.ceph.com"
CEPHFS_PROVISIONER="openshift-storage.cephfs.csi.ceph.com"
NOOBAA_PROVISIONER="openshift-storage.noobaa.io/obc"
RGW_PROVISIONER="openshift-storage.ceph.rook.io/bucket"
NOOBAA_DB_PVC="noobaa-db"
NOOBAA_BACKINGSTORE_PVC="noobaa-default-backing-store-noobaa-pvc"
#Find all the OCS StorageClasses
OCS_STORAGECLASSES=$(oc get storageclasses | grep -e "$RBD_PROVISIONER" -e "$CEPHFS_PROVISIONER" -e         "$NOOBAA_PROVISIONER" -e "$RGW_PROVISIONER" | awk '{print $1}')
# List PVCs in each of the StorageClasses
for SC in $OCS_STORAGECLASSES
 do
   echo "======================================================================"
   echo "$SC StorageClass PVCs and OBCs"
   echo "======================================================================"
   oc get pvc  --all-namespaces --no-headers 2>/dev/null | grep $SC | grep -v -e "$NOOBAA_DB_PVC" -e "  $NOOBAA_BACKINGSTORE_PVC"
   oc get obc  --all-namespaces --no-headers 2>/dev/null | grep $SC
   echo
done
