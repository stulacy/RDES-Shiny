# RDES-Shiny

This package provides a user-friendly web-app front-end to the Discrete Event Simulation `des` package, that is available [here](https://github.com/stulacy/RDES). That package provides the simulation engine that determines the transition probabilities of a specified multi-state model, which is useful when running simulations as part of a batch job, but manipulating the data into a format suitable for multi-state modelling can be very laborious. This web-app, written in the Shiny framework, provides a graphical interface for interactive use.

It has the following properties:

  - Allows the user to specify the transition matrix by graphically selecting transitions, rather than having to write up the matrix by hand. This is aided by the current state structure being displayed on screen
  - Allows the user to specify the covariates that act on each transition via simple checkboxes, rather than having to write out extensive formulae as with standard multi-state modelling in R
  - Automatically builds models from multiple parametric families and selects the one with the lowest AIC
  - In addition to reading attributes in from CSV files, they can also be provided by specifying random number distributions 
  - Transition models can be manually written, if a particular structure is known and does not need to be fitted from data. This is particularly useful when using models from literature
  - Sets up the transition parameters for input into the discrete event simulation
  - The output of the simulation, as well as all transition models can be downloaded for future use
  - Transition probabilities can be visualised on-screen with simple animations (*coming soon*)

# Running 

To run this web-app, simply clone the repo and run it via the development web-server that comes with Shiny. I do not currently have it publicly hosted.
