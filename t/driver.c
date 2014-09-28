#include <EXTERN.h>
#include <perl.h>

static PerlInterpreter *my_perl;

extern void xs_init(pTHX);

int main(int argc, char **argv, char **env)
{
    char *args[] = { NULL };
    int exitstatus, i;
    AV* plargv;

    PERL_SYS_INIT3(&argc,&argv,&env);
    my_perl = perl_alloc();
    perl_construct(my_perl);

    perl_parse(my_perl, xs_init, argc, argv, NULL);
    PL_exit_flags |= PERL_EXIT_DESTRUCT_END;

    /*** skipping perl_run() ***/

    plargv = GvAV(PL_argvgv);

    for (i = 0; i <= av_len(plargv); ++i) {
        SV **item = av_fetch(plargv, i, 0);

        call_argv(SvPV_nolen(*item), G_SCALAR | G_NOARGS, args);

        {
            dSP;
            SV *res = POPs;

            printf("RES=%s\n", SvOK(res) ? SvPV_nolen(res) : "undef");
        }
    }

    exitstatus = perl_destruct(my_perl);
    perl_free(my_perl);
    PERL_SYS_TERM();

    return exitstatus;
}
