quit -sim 

vlog -work work {..\..\..\..\Arbiter\Package\Tx_Arbiter_Package.sv}
vlog -work work {..\..\..\..\Arbiter\Ordering\ordering_if.sv}
vlog -work work {..\..\..\..\Arbiter\Ordering\ordering.sv}

#vsim -novopt -sv_seed 3477034145 work.ordering
