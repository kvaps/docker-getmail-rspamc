#!/bin/bash

chk_env() {
    eval env=\$$1
    val=${env:-$2}
    if [ -z $val ]; then
        echo "err:  Enviroment vaiable \$$1 is not set."
        exit 1
    fi  
    export "$1"="$val"
}

load_defaults() {
    chk_env TIMEOUT                "10m"
    chk_env TYPE                   "SimplePOP3SSLRetriever"
    chk_env SERVER
    chk_env USERNAME               "spam"
    chk_env PORT                   "995"
    chk_env PASSWORD
    chk_env DELETE                 "True"
    chk_env TMPDIR                 "/tmp/attachments"
    chk_env MAILDIR                "/var/spool/mail"
    chk_env RSPAMD_COMMAND         "learn_spam"
    chk_env RSPAMD_PASS
    chk_env RSPAMD_HOST
}

configure_getmail() {
    mkdir -p $MAILDIR/.getmail
    mkdir -p $MAILDIR/{cur,new,tmp}
    cat > "$MAILDIR/.getmail/getmailrc" <<EOT
[retriever]
type = $TYPE
server = $SERVER
username = $USERNAME
port = $PORT
password = $PASSWORD

[options]
delete = $DELETE

[destination]
type = Maildir
path = $MAILDIR/
EOT
    chown mail:mail -R $MAILDIR
}

check_and_learn() {
    inbox="$(su mail -s /usr/bin/getmail | grep -Po --color=none '(?<=^  )[0-9]+(?= messages)')"
    if [ "$inbox" != "0" ] ; then
        echo Getting $inbox new messages
    
        # Create TMPDIR
        mkdir -p $TMPDIR
    
        # Extract all attachmets and clear inbox
        find $MAILDIR/* -type f -exec bash -c "
            ripmime -i {} -d $TMPDIR --no-nameless --recursion-max 2 --overwrite
            echo Extract: {}
            rm -f {}
        " \;
    
        # Find extracted letters
        file_list=()
        while IFS='\n' read -d $'\n' -r file ; do
            file_list=("${file_list[@]}" "$file")
        done < <(find $TMPDIR -type f -print0 | xargs -0 file -i 2> /dev/null | grep -oP '.*(?= message/)' | grep -oP '.*(?=:)')
    
        # Create list
        for file in "${file_list[@]}"; do
            echo Found: "$file" 
            files+=' "'"$file"'"'
        done
        
        # Learn letters
        unset RSPAMC_ERROR
        eval rspamc -h $RSPAMD_HOST -P $RSPAMD_PASS $RSPAMD_COMMAND $files

        # Cleanup
        echo Cleanup
        rm -rf $TMPDIR
    
    fi

    sleep $TIMEOUT
    check_and_learn
}

echo Init
load_defaults
echo Configure getmail
configure_getmail
echo Loop started
check_and_learn
