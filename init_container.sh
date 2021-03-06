#!/usr/bin/env bash
cat >/etc/motd <<EOL 
  _____                               
  /  _  \ __________ _________   ____  
 /  /_\  \\___   /  |  \_  __ \_/ __ \ 
/    |    \/    /|  |  /|  | \/\  ___/ 
\____|__  /_____ \____/ |__|    \___  >
        \/      \/                  \/ 
A P P   S E R V I C E   O N   L I N U X

Documentation: http://aka.ms/webapp-linux
EOL
cat /etc/motd

echo "Setup openrc ..." && openrc && touch /run/openrc/softlevel

echo Starting ssh service...
rc-service sshd start

# Default to CATALINA_BASE=/home/tomcat
if [[ -z $CATALINA_BASE && -a /home/tomcat/conf/server.xml ]]
then
    export CATALINA_BASE=/home/tomcat
fi

# if IGNORE_CATALINA_BASE=1 or true, unset CATALINA_BASE
if [[ "$IGNORE_CATALINA_BASE" = "1" ||  "$IGNORE_CATALINA_BASE" = "true" ]]
then
    echo Setting CATALINA_BASE to empty as IGNORE_CATALINA_BASE is set to $IGNORE_CATALINA_BASE
    export CATALINA_BASE=
fi

if [ ! -d /home/site/wwwroot/webapps ]
then
    mkdir -p /home/site/wwwroot
    cp -r /tmp/tomcat/webapps /home/site/wwwroot
fi

# WEBSITE_INSTANCE_ID will be defined uniquely for each worker instance while running in Azure.
# During development it may not be defined, in that case  we set WEBSITE_INSTNACE_ID=dev.
if [ -z "$WEBSITE_INSTANCE_ID" ]
then
    export WEBSITE_INSTANCE_ID=dev
fi

# BEGIN: Configure App Insights

# Inject App Insights artefcats into Tomcat, if APPINSIGHTS_INSTRUMENTATIONKEY is set to a non-empty value
if [[ ! -z $APPINSIGHTS_INSTRUMENTATIONKEY ]]
then
    echo "Initializing App Insights.."
    export CATALINA_OPTS=-javaagent:/usr/local/app_insights/aiagent/applicationinsights-agent-$AI_VERSION.jar $CATALINA_OPTS
    mv /usr/local/app_insights/tomcat_lib/* /usr/local/tomcat/lib/
    mv /tmp/tomcat/conf/web.xml /usr/local/tomcat/conf/web.xml
else
    echo "Skipping App Insights initialization"
fi

# END: Configure App Insights

# BEGIN: Define JAVA OPTIONS

# Configure JAVA OPTIONS. Make sure, we append the default values instead of prepending them.
# That way, the default values take precedence and we avoid the risk of an appsetting overriding the critical (default) properties.

export JAVA_OPTS="$JAVA_OPTS -Djdk.tls.ephemeralDHKeySize=2048"
export JAVA_OPTS="$JAVA_OPTS -Djava.protocol.handler.pkgs=org.apache.catalina.webresources"
export JAVA_OPTS="$JAVA_OPTS -Djava.util.logging.config.file=/usr/local/tomcat/conf/logging.properties"
export JAVA_OPTS="$JAVA_OPTS -Djava.util.logging.manager=org.apache.juli.ClassLoaderLogManager"
export JAVA_OPTS="$JAVA_OPTS -Dsite.logdir=/home/LogFiles"
export JAVA_OPTS="$JAVA_OPTS -Dsite.home=/home"
export JAVA_OPTS="$JAVA_OPTS -Dsite.tempdir=/tmp"
export JAVA_OPTS="$JAVA_OPTS -Dport.http=80"
export JAVA_OPTS="$JAVA_OPTS -noverify"
export JAVA_OPTS="$JAVA_OPTS -Dcatalina.instance.name=$WEBSITE_INSTANCE_ID"

export _JAVA_OPTIONS="$_JAVA_OPTIONS -Djava.net.preferIPv4Stack=true"

# END: Define JAVA OPTIONS

# BEGIN: Configure ~/.profile

# After all env vars are defined, add the ones of interest to ~/.profile
# Adding to ~/.profile makes the env vars available to new login sessions (ssh) of the same user.

# list of variables that will be added to ~/.profile
export_vars=()

# Step 1. Add app settings to ~/.profile
# To check if an environment variable xyz is an app setting, we check if APPSETTING_xyz is defined as an env var
while read -r var
do
    if [ -n "`printenv APPSETTING_$var`" ]
    then
        export_vars+=($var)
    fi
done <<< `printenv | cut -d "=" -f 1 | grep -v ^APPSETTING_`

# Step 2. Add well known environment variables to ~/.profile
well_known_env_vars=( 
    CATALINA_HOME
    CATALINA_BASE
    CATALINA_OPTS
    HTTP_LOGGING_ENABLED
    WEBSITE_SITE_NAME
    WEBSITE_ROLE_INSTANCE_ID
    TOMCAT_VERSION
    JAVA_OPTS
    JAVA_HOME
    JAVA_VERSION
    TOMCAT_MAJOR
    WEBSITE_INSTANCE_ID
    _JAVA_OPTIONS
    TOMCAT_SHA1
    JAVA_ALPINE_VERSION
    JAVA_DEBIAN_VERSION
    AI_VERSION
    )

for var in "${well_known_env_vars[@]}"
do
    if [ -n "`printenv $var`" ]
    then
        export_vars+=($var)
    fi
done

# Step 3. Add environment variables with well known prefixes to ~/.profile
while read -r var
do
    export_vars+=($var)
done <<< `printenv | cut -d "=" -f 1 | grep -E "^(WEBSITE|APPSETTING|SQLCONNSTR|MYSQLCONNSTR|SQLAZURECONNSTR|CUSTOMCONNSTR)_"`

# Write the variables to be exported to ~/.profile
for export_var in "${export_vars[@]}"
do
    echo Exporting env var $export_var
    # We use single quotes to preserve escape characters
	echo export $export_var=\'`printenv $export_var`\' >> ~/.profile
done

# We want all ssh sesions to start in the /home directory
echo "cd /home" >> ~/.profile

# END: Configure ~/.profile

# BEGIN: Run startup file

# Get the startup file path
if [ -n "$1" ]
then
    # Path defined in the portal will be available as an argument to this script
    STARTUP_FILE=$1
else
    # Default startup file path
    STARTUP_FILE=/home/startup.sh
fi

# Run the startup file, if it exists
if [ -f $STARTUP_FILE ]
then
    echo Running startup file $STARTUP_FILE
    source $STARTUP_FILE
    echo Finished running startup file $STARTUP_FILE
else
    echo Looked for startup file $STARTUP_FILE, but did not find it, so skipping running it.
fi

# END: Run startup file

# Adding custom commands

#echo "net.ipv4.tcp_keepalive_intvl = 60" >> /etc/sysctl.d/00-alphine.conf
#echo "net.ipv4.tcp_keepalive_probes = 10" >> /etc/sysctl.d/00-alphine.conf
#echo "net.ipv4.tcp_keepalive_time = 60" >> /etc/sysctl.d/00-alphine.conf


# Start Tomcat
echo Starting Tomcat with CATALINA_BASE set to \"$CATALINA_BASE\"
catalina.sh run
