---
title: Home Page
layout: front
---
{% include JB/setup %}

<!-- Example row of columns -->
<div class="row">
  <div class="col-lg-4">
     <h3>SML'97</h3>
       <img width="100" alt="The Definition" align="right" src="{{BASE_PATH}}/images/Thedef.jpg">
       <p>The MLKit compiler covers all of Standard ML,
          as defined in the 1997 edition of the Definition of Standard ML. The
          MLKit implements most of the latest Standard ML Basis Library
          specification.</p>
   </div>
   <div class="col-lg-4">
     <h3>ML Basis Files</h3>
       <p>The MLKit compiles large
          programs, including itself, around 80.000 lines of Standard ML plus
          the Standard ML Basis Library. The support for ML Basis Files makes it
          easy to compile large programs with different Standard ML
          compilers. Currently, both MLton and the MLKit supports the concept of
          ML Basis Files. The MLKit has a system, based on MLB-files, for
          avoiding unnecessary recompilation upon changes of source code.</p>
       <p><a class="btn btn-primary" href="{{BASE_PATH}}/mlbasisfiles.html" role="button">View details &raquo;</a></p>
   </div>
   <div class="col-lg-4">
     <h3>Region-Based</h3>
       <p>The MLKit integrates reference-tracing garbage collection with region-based memory
          management. Memory allocation directives (both allocation and
          deallocation) are inferred by the compiler, which uses a number of
          program analyses concerning lifetimes and storage layout.</p>
       <p><a class="btn btn-primary" href="{{BASE_PATH}}/doc.html" role="button">View documentation &raquo;</a></p>
  </div>
</div>

<!-- Example row of columns -->
<div class="row">
  <div class="col-lg-4">
     <h3>Open Source</h3>
       <p>MLKit is open source; it is
          distributed under the GNU General Public License (GPL). The runtime
          system and libraries are also distributed under the MIT licence, thus,
          executables constructed with the MLKit are non-restricted.</p>
   </div>
   <div class="col-lg-4">
     <h3>Region Profiling</h3>
       <img width="100" alt="Life profile" align="right" src="{{BASE_PATH}}/images/Life80_large.jpg">
       <p>The MLKit includes a graphical region
          profiler, which helps gain detailed control over memory reuse. The
          example graph to the right shows a region profile (region sizes as a
          function of time) of two hundred generations of the `Game of
          Life'.</p>
   </div>
   <div class="col-lg-4">
     <h3>Good for Real-Time</h3>
       <p>Programmers who are interested in
          real-time programming can exploit the possibility of disabling
          reference-tracing garbage collection. In this case, there will be no
          interruptions of unbounded duration at runtime.</p>
  </div>
</div>

<!-- Example row of columns -->
<div class="row">
  <div class="col-lg-4">
     <h3>Interface to C</h3>
       <p>MLKit applications can call C functions
          using standard C calling conventions; the region scheme can even take
          care of allocating and deallocating regions used by C functions thus
          invoked.</p>
   </div>
   <div class="col-lg-4">
     <h3>No-Overhead Modules</h3>
       <p>The MLKit compiles Standard ML Modules, using a compilation scheme called 
          <a href="{{BASE_PATH}}/staticinterp.html">Static Interpretation</a>, which eliminates Modules entirely at compile
          time.</p>
   </div>
   <div class="col-lg-4">
     <h3>Two Backends</h3>
       <p>Two backends are provided, one that
          generates x86 native machine code for the Linux and MacOS operating
          systems and one that generates bytecode.</p>
  </div>
</div>

<!-- Example row of columns -->
<div class="row">
  <div class="col-lg-4">
     <h3>Hosted at Github</h3>
       <p>MLKit sources are <a href="http://github.com/melsman/mlkit">hosted at Github</a>, which makes it straightforward to browse code and collaborate on projects.</p>
   </div>
   <div class="col-lg-4">
     <h3>Related Systems</h3>
       <p>Several systems are built on top of MLKit, including:
          <ul>
            <li><a href="http://www.smlserver.org">SMLserver</a> - a system for developing server based Web applications in Standard ML.</li>
            <li><a href="http://www.smlserver.org/smltojs">SMLtoJs</a> - a compiler that compiles Standard ML programs into JavaScript.</li>
            <li><a href="http://www.smlserver.org/ide">SMLonline</a> - a Standard ML compiler running in a browser.</li>
          </ul> 
          </p>
   </div>
</div>