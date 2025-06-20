# load variables and makefile config
include Makefile.config

# load possible overrides or non-free definitions
-include Makefile.local

# services
services-amd64: $(SERVICES_AMD64:%=packer-%)
services-arm64: $(SERVICES_ARM64:%=packer-%)

# allow individual services targets (e.g., "make service_Lithops")
$(SERVICES): %: packer-%

# aliases + dependency
packer-%: $(DIR_EXPORT)/%.qcow2
	@$(INFO) 'Packer $* done'

# run packer build for given distro or service
$(DIR_EXPORT)/%.qcow2:
	$(eval DISTRO_NAME := $(shell echo $* | sed 's/[0-9\.].*//'))
	$(eval DISTRO_VER  := $(shell echo $* | sed 's/^.[^0-9\.]*\(.*\)/\1/'))
	packer/build.sh '$(DISTRO_NAME)' '$(DISTRO_VER)' $@

clean:
	-if [ -d '$(DIR_EXPORT)' ]; then rm -rf $(DIR_EXPORT)/*; fi

help:
	@echo 'Usage examples:'
	@echo '    make <service>               -- build just one service'
	@echo
	@echo '    make services-amd64          -- build all services (amd64)'
	@echo '    make services-arm64          -- build all services (arm64)'
	@echo
	@echo '    make services-amd64 -j 4     -- build all amd64 services in 4 parallel tasks'
	@echo
	@echo 'Available services:'
	@echo '    $(SERVICES_AMD64)'
	@echo
	@echo 'Available services (arm64):'
	@echo '    $(SERVICES_ARM64)'
	@echo

version:
	@echo $(VERSION)-$(RELEASE) > version
