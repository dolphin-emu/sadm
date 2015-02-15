# Second stage of the server startup. Ran by the first stage after having
# updated the Git repository.
#
# Responsible for starting up all services, including:
# * The killswitch.
# * The buildslave.

cd \buildslave
start-process buildslave start

# TODO(delroth): killswitch.
