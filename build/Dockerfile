FROM lamw/vibauthor

# Copy all files to the container
COPY . letsencrypt-esxi-dns

# Run VIB build script
RUN /bin/bash letsencrypt-esxi-dns/build/create_vib.sh

CMD ["/bin/bash"]
