#
#                Setting and dressing of adel plants
#
#
#Utilities foor reconstructing a plant from parameters
#
openapprox <- function(x,y,xout,extrapolate=TRUE) {
  xy <- cbind(x,y)
  xy <- xy[order(xy[,1]),]
  res <- approx(xy[,1],xy[,2],xout = xout,rule=2)$y
  last <- nrow(xy)
  twolast <- c(last - 1,last)
  if (extrapolate) {
    lastrate <- diff(xy[twolast,2]) / diff(xy[twolast,1])
    firstrate <- diff(xy[1:2,2]) / diff(xy[1:2,1])
  } else {
    lastrate <- 0
    firstrate <- 0
  }
  extrax <- xout > xy[last,1]
  res[extrax] <- xy[last,2] + lastrate * (xout[extrax] - xy[last,1])
  extrax <- xout < xy[1,1]
  res[extrax] <- xy[1,2] +  firstrate * (xout[extrax] - xy[1,1])
  res
}
#
#extract or replicate a desired number of plant from a canopy table
#
setCanopy <- function(canT, nplants=1, randomize = TRUE, seed = NULL) {
  if (!is.null(seed))
    set.seed(seed)
  out <- vector("list",nplants)
  plantdb <- by(canT,list(canT$plant),function(x) x)
  if (randomize)
    plnb <- ceiling(runif(nplants) * length(plantdb))
  else
    plnb <- rep(seq(length(plantdb)),len=nplants)
  for (p in seq(out)) {
    pT <- plantdb[[plnb[p]]]
    pT$plant <- p
    if (randomize)
      pT$Laz <- (pT$Laz + 360 * runif(1)) %% 360
    out[[p]] <- pT
  }
  do.call("rbind",out)
}
  
#
predictDim <- function(dimT,index,nf) {
  res <- NULL
  if (!index %in% dimT$index)
    stop(paste("setAdel : dimIndex", index, "not found in dimTable"))
  else {
    nout <- seq(nf)/nf 
    dim <- dimT[dimT$index == index,]
    out <- vector("list",ncol(dimT)-2)
    names(out) <- colnames(dim)[-match(c('index','nrel'),colnames(dim))]
    for (w in names(out))
      out[[w]] <- approx(dim$nrel,dim[,w],nout,rule=2)$y
    res <- data.frame(do.call("cbind",out))
  }
  res
}
#
predictPhen <- function(phenT,index,nf,datesf1) {
  if (!"disp"%in%colnames(phenT))
    stop("Missing input for leaf desapearance in phenT (see docAdel.txt")
  res <- NULL
  if (!index %in% phenT$index)
    stop(paste("setAdel : phenIndex", index, "not found in phenTable"))
  else {
    nout <- c(0,seq(nf))/nf
    phen <- phenT[phenT$index == index,]
    out <- vector("list",ncol(phenT) -2)
    names(out) <- colnames(phen)[-match(c('index','nrel'),colnames(phen))]
    names(datesf1) <- c("tip","col","ssi","disp")
    for (i in 1:4) {
      w <- names(out)[i]
      out[[w]] <- openapprox(phen$nrel,phen[,w],nout) + datesf1[[w]] 
    }
    res <- data.frame(cbind(n=c(0,seq(nf)),do.call("cbind",out)))
  }
  res
}
#
#peduncle elongation
#
predictPed <- function(pheno,phyto,index,nf,earT) {
  par <- earT[index,]
  rate <- 0
  if (par$em_ped - par$em_ear > 0)
    rate <- par$l_ear / (par$em_ped - par$em_ear)
  start <- pheno[pheno$n==nf,"col"] + par$em_ped - phyto[nf,"Gl"] / ifelse(rate == 0,1,rate)
  end <- start + par$l_ped / ifelse(rate == 0,1,rate)
  data.frame(startPed=start,endPed=end,senPed=pheno[pheno$n==nf,"col"] + par$end_gf)
}

  
#setAdel performs the dressing (geometry, tiller number ...) of plants from parameters and duplicate them for a given number of outputed plants
#
setAdel <- function(axeT,dimT,phenT,earT,ssisenT,geoLeaf,geoAxe,nplants=1,sample='random',seed=NULL,xy_db=NULL,sr_db=NULL) {

  #prise en chage nouveaux noms
  conv <- c("id_plt","id_axis","N_phytomer","TT_stop_axis","TT_del_axis","id_dim","id_phen","id_ear","TT_em_phytomer1","TT_col_phytomer1","TT_sen_phytomer1","TT_del_phytomer1")
  names(conv) <- c("plant","axe","nf","end","disp","dimIndex","phenIndex","earIndex","emf1","ligf1","senf1","dispf1")
  colnames(axeT)[colnames(axeT) %in% conv] <- names(conv)[na.omit(match(colnames(axeT),conv))]
  #
  conv <- c("id_dim","index_rel_phytomer","L_blade","W_blade","L_sheath","W_sheath","L_internode","W_internode")
  names(conv) <- c("index","nrel","Ll","Lw","Gl","Gd","El","Ed")
  colnames(dimT)[colnames(dimT) %in% conv] <- names(conv)[na.omit(match(colnames(dimT),conv))]
  #
  conv <- c("id_phen","index_rel_phytomer","dTT_em_phytomer","dTT_col_phytomer","dTT_sen_phytomer","dTT_del_phytomer")
  names(conv) <- c("index","nrel","tip","col","ssi","disp")
  colnames(phenT)[colnames(phenT) %in% conv] <- names(conv)[na.omit(match(colnames(phenT),conv))]
  #
  conv <- c("id_ear","dTT_em_ear","dTT_em_peduncle","TT_z92","L_peduncle","W_peduncle","L_ear","A_ear","L_spike")
  names(conv) <- c("index","em_ear","em_ped","end_gf","l_ped","d_ped","l_ear","Sp_ear","l_ear_awn")
  colnames(earT)[colnames(earT) %in% conv] <- names(conv)[na.omit(match(colnames(earT),conv))]
  
  #verif inputs et completion default values
  if (!is.null(seed))
    set.seed(seed)
  
  if (is.null(earT)) {
    iear <- grep("earIndex",colnames(axeT),fixed=TRUE)
    if (length(iear) > 0) {
      earindex <- axeT[,iear]
      axeT <- axeT[,-iear]
    }
    axeT <- cbind(axeT,earIndex = 1)
    #protect no-ear axes from default ear restoration
    axeT$earIndex <- ifelse(is.na(earindex),NA,axeT$earIndex)
    earT <- data.frame(index = 1,em_ear = 100, em_ped = 200, end_gf = 1000, l_ped = 0, d_ped = 0, l_ear = 0, Sp_ear = 0, l_ear_awn = 0)
  }
  
  if (is.null(ssisenT))
    ssisenT <- data.frame(ndel=1:4,rate1=0.07,dssit1=c(0,1.2,2.5,3),dssit2=c(1.2,2.5,3.7,4))
 
  if (!"incB"%in%colnames(dimT)) 
    dimT <- cbind(dimT,incB = -999,dincB = 0)
  useAzim <- FALSE
  if (!"pAngle"%in%colnames(dimT)) {
    useAzim <- TRUE
    dimT <- cbind(dimT,pAngle = -999,dpAngle = 0)
  }
  
  plantdb <- by(axeT,list(axeT$plant),function(x) {
    if (! 0 %in% x$axe)
      stop(paste("No main stem found for plant",x$plant[1],", Check axeT table"))
    x})
  #sampling nplants in the database
  if (sample == 'random')
    plnb <- ceiling(runif(nplants) * length(unique(axeT$plant)))
  else
    plnb <- rep(seq(plantdb),lenght.out=nplants)[1:nplants]
  #
  out <- vector("list",nplants)
  names(out) <- names(plantdb)[plnb]
  for (p in seq(out)) {
    #axeTable from axeT and geoAxe or dimT if azim/azdev in colums
    pT <- plantdb[[plnb[p]]]
    axeTable <- data.frame(axe = pT$axe,
                           nf = pT$nf,
                           emf1 = pT$emf1,
                           end = pT$end,
                           disp = pT$disp,
                           azT = sapply(pT$axe,geoAxe$azT),
                           incT = sapply(pT$axe,geoAxe$incT),
                           dredT = sapply(pT$axe,geoAxe$dredT),
                           hasEar = !is.na(pT$earIndex)
                           )
    #phytoT from dimT and geoleaf
    nomsdim <- c("Ll","Lw","Gl","Gd","El","Ed","pAngle","dpAngle","incB","dincB")
    #row = phytomer number + 3 (peduncle, ear, awns)
    nfM <- max(pT$nf) + 3
    phytoT <- array(NA,dim=c(nfM,length(nomsdim)+3,nrow(pT)),dimnames=list(seq(nfM),c(nomsdim,"Azim","Lindex","Lseed"),pT$axe))
    for (a in seq(nrow(pT))) {
      nf <- pT$nf[a]
      pred <- predictDim(dimT,pT$dimIndex[a],nf)[,nomsdim]
      if (!is.null(pred))
        phytoT[seq(nf),nomsdim,a] <- unlist(pred)
      phytoT[seq(nf),"incB",a] <- phytoT[seq(nf),"incB",a] + (runif(nf) - .5) * phytoT[seq(nf),"dincB",a]
      if (useAzim) 
        phytoT[seq(nf),"Azim",a] <- sapply(seq(nf),function(n) geoLeaf$Azim(a,n,nf-n))
      else
        phytoT[seq(nf),"Azim",a] <- phytoT[seq(nf),"pAngle",a] + (runif(nf) - .5) * phytoT[seq(nf),"dpAngle",a]
      #
      lindex <- sapply(seq(nf),function(n) geoLeaf$Lindex(a,n,nf-n))
      lseed <- runif(nf)
      if (is.null(xy_db)) {
        phytoT[seq(nf),"Lindex",a] <- lindex
        phytoT[seq(nf),"Lseed",a] <- lseed
      }
      else  {
        lindex <- sapply(lindex,function(x) ifelse(x %in% seq(xy_db),x,seq(xy_db)[which.min(abs(x - seq(xy_db)))]))
        lindex <- sapply(lindex,function(x) ifelse(x %in% seq(sr_db),x,seq(sr_db)[which.min(abs(x - seq(sr_db)))]))
        phytoT[seq(nf),"Lindex",a] <- lindex
        phytoT[seq(nf),"Lseed",a] <- sapply(seq(lseed),function(x) round(lseed[x] * length(xy_db[[lindex[x]]])))
      }
      #
      phytoT[(nf+1):(nf+3),,a] <- 0
      if (!is.na(pT$earIndex[a])) {
        phytoT[(nf+1):(nf+2),"El",a] <- unlist(earT[pT$earIndex[a],c("l_ped","l_ear")])
        phytoT[nf+3,"El",a] <- unlist(earT[pT$earIndex[a],"l_ear_awn"] - earT[pT$earIndex[a],"l_ear"])
        phytoT[nf+1,"Ed",a] <- unlist(earT[pT$earIndex[a],"d_ped"])
        if (earT[pT$earIndex[a],"l_ear"] > 0)
          phytoT[(nf+2):(nf+3),"Ed",a] <- unlist(earT[pT$earIndex[a],"Sp_ear"]/earT[pT$earIndex[a],"l_ear"])
      }
    }
    #tip, collar and ssi : table input for oppenapprox
    phenoT <- vector("list",nrow(pT))
    names(phenoT) <- pT$axe
    if (!"dispf1"%in%colnames(pT))
      print("Missing input for leaf desapearance in axeT (see docAdel.txt")
    for (a in seq(nrow(pT)))
      phenoT[[a]] <- predictPhen(phenT,pT$phenIndex[a],pT$nf[a],pT[a,c("emf1","ligf1","senf1","dispf1")])
    # date of start and end of peduncle elongation
    pedT <- vector("list",nrow(pT))
    names(pedT) <- pT$axe
    for (a in seq(nrow(pT))) 
      if (!is.na(pT$earIndex[a]))
        pedT[[a]] <- predictPed(phenoT[[a]],phytoT[,,a],pT$earIndex[a],pT$nf[a],earT)
    
    out[[p]] <- list(refp=names(out)[p],axeT = axeTable,phytoT=phytoT,pheno=phenoT,pedT = pedT,ssisenT=ssisenT)
  }
  out
}

