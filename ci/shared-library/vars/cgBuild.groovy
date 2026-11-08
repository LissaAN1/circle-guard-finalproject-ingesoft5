// Compiles and assembles the changed services.
def call() {
    cgGradle(env.CG_SERVICES.split() as List<String>, 'assemble')
}
