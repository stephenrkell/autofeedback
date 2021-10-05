#ifndef CO557_H_
#define CO557_H_

#ifndef MODULE
#error "Must have MODULE macro defined"
#endif

#define _scriptdir(module) \
	"/usr/l/courses/" #module "/autofeedback/lib" #module "/scripts"
/* Preprocessor wackiness: to expand MODULE, must pass through a macro layer */
#define scriptdir(module) _scriptdir(module)
#define _helper_filename(helpername) scriptdir(MODULE) "/" #helpername

#endif
