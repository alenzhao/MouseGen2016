#library(analogsea)
library(parallel)
library(doParallel)
library(devtools)
# I needed this in June 2016 to get droplets_create().
install_github("sckott/analogsea")
library(analogsea)

Sys.setenv(DO_PAT = "*** REPLACE THIS BY YOUR DIGITAL OCEAN API KEY ***")

participants <- read.csv("MouseGen2016_roster.csv", as.is=TRUE)
N = nrow(participants)

# Single machine.
#img = images(private = TRUE)[["mousegen2016"]]
#d = droplet_create(name = "droplet2", size = "8gb", image = img[["id"]],
#                   region = "nyc2")

# We have to make the e-mail addresses have only A-Z, a-z, . and -.
email.column = "Email_Address"
participants[,email.column] = make.names(participants[,email.column])
participants[,email.column] = gsub("_", ".", participants[,email.column])
chars = sort(unique(unlist(strsplit(participants[,email.column], split = ""))))
stopifnot(chars %in% c(LETTERS, letters, 0:9, ".", "-"))

# Trying new command to make multiple machines at once.
img = images(private = TRUE)[["mousegen2016"]]
# NOTE: You may get an error if you create more than 10 machines.  Just make
#       multiple calls to this function and stack up the droplets.
droplet_list = droplets_create(names = participants[1:10,email.column], size = "8gb", image = img[["id"]],
                               region = "nyc2")
droplet_list[11:20] = droplets_create(names = participants[11:20,email.column], size = "8gb", image = img[["id"]],
                               region = "nyc2")
droplet_list[21:N] = droplets_create(names = participants[21:N,email.column], size = "8gb", image = img[["id"]],
                               region = "nyc2")

# start docker containers
for(i in 1:N) {
  print(i)
  # select droplet
  d = droplet(droplet_list[[i]]$id)
  
  # start the container.
  d %>% docklet_run("-d", " -v /data:/data", " -v /tutorial:/tutorial", " -p 8787:8787", 
                    " -e USER=rstudio", " -e PASSWORD=mousegen ", "--name myrstudio ", "churchill/ibangs2016") %>%
                    droplet_wait()

  # add symbolic links
  lines2 <- "docker exec myrstudio ln -s /data /home/rstudio/data
             docker exec myrstudio ln -s /tutorial /home/rstudio/tutorial"
  cmd2 <- paste0("ssh ", analogsea:::ssh_options(), " ", "root", "@", analogsea:::droplet_ip(d)," ", shQuote(lines2))
  analogsea:::do_system(d, cmd2, verbose = TRUE)
} # for(i)

# Add the IP address to the participant list.
participants = read.csv("MouseGen2016_roster.csv", as.is=TRUE)
participants = data.frame(participants, IP.address = rep(NA, nrow(participants)))
for(i in 1:nrow(participants)) {
  print(i)
  # select droplet
  d = droplet(droplet_list[[i]]$id)
  participants$IP.address[i] = d$networks$v4[[1]]$ip_address
} # for(i)
participants$IP.address = paste0("http://", participants$IP.address, ":8787")
write.table(participants, "MouseGen2016_roster_withIP.tsv", quote = FALSE, 
            row.names = FALSE, sep = "\t")

#############################################################################
# NOTE: Didn't use the following for the course. I just sent e-mails by hand.
#############################################################################

### Create participant table with links
participants$DO_machine <- sapply(droplet_list, function(x) x$name)
participants$link_RStudio <- sapply(droplet_list, function(x) paste0("http://",analogsea:::droplet_ip(x),":8787"))

library(xtable)
sanitize.text.function <- function(x) {
  idx <- substr(x, 1, 7) == "http://"
  x[idx] <- paste0('<a href="',x[idx],'">',sub("^http://","",x[idx]),'</a>')
  x
}
cols <- c("Name", "DO_machine", "link_RStudio")
print(xtable(participants[,cols], caption="Digital Ocean Machines"),
      type = "html", sanitize.text.function = sanitize.text.function,
      file = "dolist.html", include.rownames=FALSE)

### Send emails to course participants
library(mailR)


for (i in 1:N) {
  email_body <- paste0("Dear ",participants$Name[i],",\n\n",
                       "During the workshop, you will need an access to RStudio Server ",
                       "running on your personal Digital Ocean virtual machine. You can access the machine ",
                       "in your web browser:\n\n",
                       participants$link_RStudio[i]," (user:rstudio, password:ibangs)\n\n",
                       "After the workshop you can run this docker image either on your personal machine or host it ",
                       "on Digital Ocean (as we did). Further instructions can be found on https://github.com/churchill-lab/IBANGS2016 or https://github.com/churchill-lab/sysgen2015.\n\n",
                       "Best regards,\n\n","Petr Simecek")
  
  send.mail(from = "REPLACE THIS BY YOUR_GMAIL@gmail.com",
            to = participants$Email[i],
            replyTo = "REPLACE THIS BY YOUR_EMAIL",
            subject = "IBANGS - DO Machine Access",
            body = email_body,
            smtp = list(host.name = "smtp.gmail.com", port = 465, 
                        user.name = "REPLACE THIS BY YOUR_GMAIL@gmail.com", 
                        passwd = "***YOUR PASSWORD***", ssl = TRUE),
            authenticate = TRUE,
            send = TRUE)
}

# Loop to kill all machines.
#for(i in 1:N) {
#  d = droplet(droplet_list[[i]]$id)
#  droplet_delete(d)
#} # for(i)
