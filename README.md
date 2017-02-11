# fai
Code for Docker image of FAI [Fully Automatic Installation](http://fai-project.org/) 4.3.3.  With this image you may create FAI ISO's for Trusted Builds.

* To use this image:

`docker run --name fai --privileged -it ricardobranco/fai:4.3.3`

* Inside the container you must run **fai-setup**:

`fai-setup -vl`

* When the command is finished you may **exit** the container and commit a new image for reuse:

`docker commit fai fai-setup && docker rm -v fai`

* Then you can use the **fai-setup** image with your FAI configuration:

`docker run --name fai -v ~/fai:/srv/fai/config --privileged -it fai-setup`

* Inside the container you must run the **fai-mirror.sh** script to create a suitable mirror:

`fai-mirror.sh HOSTNAME`

* Validate the mirror with the **checkpkgs.sh** script to check its integrity:

`checkpkgs.sh /tmp/mirror`

* You may commit a new **_fai-mirror_** image or save the mirror with [docker-cp](https://docs.docker.com/engine/reference/commandline/cp/):

`docker cp fai:/tmp/mirror mirror.HOSTNAME

* Edit the **menuentry** at /etc/fai/grub.cfg.  Note: Don't forget to also change the Grub user and password, which defaults to "fai".

`vi /etc/fai/grub.cfg`

* Inside the container, run the **fai-cd.sh** script to generate a FAI ISO:

`fai-cd.sh HOSTNAME`

* The ISO is /tmp/fai-full.iso.  Use [docker-cp](https://docs.docker.com/engine/reference/commandline/cp/) to get it from the container:

`docker cp fai:/tmp/fai-full.iso .`

* At this point you may **exit** and remove the container.

* To reliably burn the ISO to an USB stick, use the **burniso.sh** script provided in the utils/ directory:

`burniso.sh /tmp/fai-full.iso`


NOTES:

* This image is based on Ubuntu 16.04 to create Ubuntu 16.04 ISO images.  With minimal modifications (Dockerfile and fai/NFSROOT) it's possible to create Debian 7 & 8 images, as well as Ubuntu 14.04.

* With a bit of tweaking, it should be possible to setup a container as a FAI server over the network.
