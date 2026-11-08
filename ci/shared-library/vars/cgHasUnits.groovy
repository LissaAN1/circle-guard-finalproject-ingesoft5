// True when the current build has units of the given kind ('service' or 'client').
def call(String kind) {
    String units = (kind == 'service') ? env.CG_SERVICES : env.CG_CLIENTS
    return units?.trim() ? true : false
}
