#include <EXTERN.h>
#include <perl.h>

static PerlInterpreter *my_perl;

extern void xs_init(pTHX);

int main(int argc, char **argv, char **env)
{
    char *args[] = { NULL };
    int exitstatus;
    PERL_SYS_INIT3(&argc,&argv,&env);
    my_perl = perl_alloc();
    perl_construct(my_perl);

    perl_parse(my_perl, xs_init, argc, argv, NULL);
    PL_exit_flags |= PERL_EXIT_DESTRUCT_END;

    /*** skipping perl_run() ***/

    call_argv("test", G_DISCARD | G_NOARGS, args);

    exitstatus = perl_destruct(my_perl);
    perl_free(my_perl);
    PERL_SYS_TERM();

    return exitstatus;
}
