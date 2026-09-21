# A real Active Directory Domain Controller -- Samba4 AD DC, not a mock.
# Genuine Kerberos KDC, LDAP directory, DNS, and SYSVOL/GPO storage,
# interoperable with real Windows clients over the wire. No Windows
# license needed: Samba4's AD DC implementation is open source and is
# a well-established way to run a real AD domain without a Windows
# Server box underneath it.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      samba \
      samba-ad-provision \
      samba-dsdb-modules \
      samba-vfs-modules \
      winbind \
      smbclient \
      krb5-user \
      krb5-config \
      ldb-tools \
      dnsutils \
      ldap-utils \
      acl \
    && rm -rf /var/lib/apt/lists/*

COPY provision.sh /provision.sh
COPY seed-objects.sh /seed-objects.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /provision.sh /seed-objects.sh /entrypoint.sh

EXPOSE 53/tcp 53/udp 88/tcp 88/udp 135/tcp 389/tcp 389/udp 445/tcp 464/tcp 464/udp 636/tcp 3268/tcp 3269/tcp

ENTRYPOINT ["/entrypoint.sh"]
