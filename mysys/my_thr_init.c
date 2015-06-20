/* Copyright (c) 2000, 2015, Oracle and/or its affiliates. All rights reserved.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; version 2 of the License.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301  USA */

/*
  Functions to handle initializating and allocationg of all mysys & debug
  thread variables.
*/

#include "mysys_priv.h"
#include "my_sys.h"
#include <m_string.h>
#include <signal.h>
#include "my_thread_local.h"

static my_bool THR_KEY_mysys_initialized= FALSE;
static my_bool my_thread_global_init_done= FALSE;
static uint    THR_thread_count= 0;
static uint    my_thread_end_wait_time= 5;
static my_thread_id thread_id= 0;
static thread_local_key_t THR_KEY_mysys;

mysql_mutex_t THR_LOCK_malloc, THR_LOCK_open,
              THR_LOCK_lock, THR_LOCK_myisam, THR_LOCK_heap,
              THR_LOCK_net, THR_LOCK_charset, THR_LOCK_threads,
              THR_LOCK_myisam_mmap;
mysql_cond_t  THR_COND_threads;

#ifdef PTHREAD_ADAPTIVE_MUTEX_INITIALIZER_NP
native_mutexattr_t my_fast_mutexattr;
#endif
#ifdef PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP
native_mutexattr_t my_errorcheck_mutexattr;
#endif
#ifdef _WIN32
static void install_sigabrt_handler();
#endif


/**
  Re-initialize components initialized early with @c my_thread_global_init.
  Some mutexes were initialized before the instrumentation.
  Destroy + create them again, now that the instrumentation
  is in place.
  This is safe, since this function() is called before creating new threads,
  so the mutexes are not in use.
*/

void my_thread_global_reinit()
{
  struct st_my_thread_var *tmp;

  DBUG_ASSERT(my_thread_global_init_done);

#ifdef HAVE_PSI_INTERFACE
  my_init_mysys_psi_keys();
#endif

  mysql_mutex_destroy(&THR_LOCK_heap);
  mysql_mutex_init(key_THR_LOCK_heap, &THR_LOCK_heap, MY_MUTEX_INIT_FAST);

  mysql_mutex_destroy(&THR_LOCK_net);
  mysql_mutex_init(key_THR_LOCK_net, &THR_LOCK_net, MY_MUTEX_INIT_FAST);

  mysql_mutex_destroy(&THR_LOCK_myisam);
  mysql_mutex_init(key_THR_LOCK_myisam, &THR_LOCK_myisam, MY_MUTEX_INIT_SLOW);

  mysql_mutex_destroy(&THR_LOCK_malloc);
  mysql_mutex_init(key_THR_LOCK_malloc, &THR_LOCK_malloc, MY_MUTEX_INIT_FAST);

  mysql_mutex_destroy(&THR_LOCK_open);
  mysql_mutex_init(key_THR_LOCK_open, &THR_LOCK_open, MY_MUTEX_INIT_FAST);

  mysql_mutex_destroy(&THR_LOCK_charset);
  mysql_mutex_init(key_THR_LOCK_charset, &THR_LOCK_charset, MY_MUTEX_INIT_FAST);

  mysql_mutex_destroy(&THR_LOCK_threads);
  mysql_mutex_init(key_THR_LOCK_threads, &THR_LOCK_threads, MY_MUTEX_INIT_FAST);

  mysql_cond_destroy(&THR_COND_threads);
  mysql_cond_init(key_THR_COND_threads, &THR_COND_threads);

  tmp= mysys_thread_var();
  DBUG_ASSERT(tmp);

  mysql_cond_destroy(&tmp->suspend);
  mysql_cond_init(key_my_thread_var_suspend, &tmp->suspend);
}


/**
  initialize thread environment

  @retval  FALSE  ok
  @retval  TRUE   error (Couldn't create THR_KEY_mysys)
*/

my_bool my_thread_global_init()
{
  int pth_ret;

  if (my_thread_global_init_done)
    return FALSE;
  my_thread_global_init_done= TRUE;

#if defined(SAFE_MUTEX)
  safe_mutex_global_init();		/* Must be called early */
#elif defined(MY_PTHREAD_FASTMUTEX)
  fastmutex_global_init();              /* Must be called early */
#endif

#ifdef PTHREAD_ADAPTIVE_MUTEX_INITIALIZER_NP
  /*
    Set mutex type to "fast" a.k.a "adaptive"

    In this case the thread may steal the mutex from some other thread
    that is waiting for the same mutex.  This will save us some
    context switches but may cause a thread to 'starve forever' while
    waiting for the mutex (not likely if the code within the mutex is
    short).
  */
  pthread_mutexattr_init(&my_fast_mutexattr);
  pthread_mutexattr_settype(&my_fast_mutexattr,
                            PTHREAD_MUTEX_ADAPTIVE_NP);
#endif

#ifdef PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP
  /*
    Set mutex type to "errorcheck"
  */
  pthread_mutexattr_init(&my_errorcheck_mutexattr);
  pthread_mutexattr_settype(&my_errorcheck_mutexattr,
                            PTHREAD_MUTEX_ERRORCHECK);
#endif

  DBUG_ASSERT(! THR_KEY_mysys_initialized);
  if ((pth_ret= my_create_thread_local_key(&THR_KEY_mysys, NULL)) != 0)
  { /* purecov: begin inspected */
    my_message_local(ERROR_LEVEL, "Can't initialize threads: error %d",
                     pth_ret);
    /* purecov: end */
    return TRUE;
  }
  THR_KEY_mysys_initialized= TRUE;

  mysql_mutex_init(key_THR_LOCK_malloc, &THR_LOCK_malloc, MY_MUTEX_INIT_FAST);
  mysql_mutex_init(key_THR_LOCK_open, &THR_LOCK_open, MY_MUTEX_INIT_FAST);
  mysql_mutex_init(key_THR_LOCK_charset, &THR_LOCK_charset, MY_MUTEX_INIT_FAST);
  mysql_mutex_init(key_THR_LOCK_threads, &THR_LOCK_threads, MY_MUTEX_INIT_FAST);
  mysql_mutex_init(key_THR_LOCK_lock, &THR_LOCK_lock, MY_MUTEX_INIT_FAST);
  mysql_mutex_init(key_THR_LOCK_myisam, &THR_LOCK_myisam, MY_MUTEX_INIT_SLOW);
  mysql_mutex_init(key_THR_LOCK_myisam_mmap, &THR_LOCK_myisam_mmap, MY_MUTEX_INIT_FAST);
  mysql_mutex_init(key_THR_LOCK_heap, &THR_LOCK_heap, MY_MUTEX_INIT_FAST);
  mysql_mutex_init(key_THR_LOCK_net, &THR_LOCK_net, MY_MUTEX_INIT_FAST);
  mysql_cond_init(key_THR_COND_threads, &THR_COND_threads);

  return FALSE;
}


void my_thread_global_end()
{
  struct timespec abstime;
  my_bool all_threads_killed= TRUE;

  set_timespec(&abstime, my_thread_end_wait_time);
  mysql_mutex_lock(&THR_LOCK_threads);
  while (THR_thread_count > 0)
  {
    int error= mysql_cond_timedwait(&THR_COND_threads, &THR_LOCK_threads,
                                    &abstime);
    if (error == ETIMEDOUT || error == ETIME)
    {
#ifndef _WIN32
      /*
        We shouldn't give an error here, because if we don't have
        pthread_kill(), programs like mysqld can't ensure that all threads
        are killed when we enter here.
      */
      if (THR_thread_count)
        /* purecov: begin inspected */
        my_message_local(ERROR_LEVEL, "Error in my_thread_global_end(): "
                         "%d threads didn't exit", THR_thread_count);
        /* purecov: end */
#endif
      all_threads_killed= FALSE;
      break;
    }
  }
  mysql_mutex_unlock(&THR_LOCK_threads);

  DBUG_ASSERT(THR_KEY_mysys_initialized);
  my_delete_thread_local_key(THR_KEY_mysys);
  THR_KEY_mysys_initialized= FALSE;
#ifdef PTHREAD_ADAPTIVE_MUTEX_INITIALIZER_NP
  pthread_mutexattr_destroy(&my_fast_mutexattr);
#endif
#ifdef PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP
  pthread_mutexattr_destroy(&my_errorcheck_mutexattr);
#endif
  mysql_mutex_destroy(&THR_LOCK_malloc);
  mysql_mutex_destroy(&THR_LOCK_open);
  mysql_mutex_destroy(&THR_LOCK_lock);
  mysql_mutex_destroy(&THR_LOCK_myisam);
  mysql_mutex_destroy(&THR_LOCK_myisam_mmap);
  mysql_mutex_destroy(&THR_LOCK_heap);
  mysql_mutex_destroy(&THR_LOCK_net);
  mysql_mutex_destroy(&THR_LOCK_charset);
  if (all_threads_killed)
  {
    mysql_mutex_destroy(&THR_LOCK_threads);
    mysql_cond_destroy(&THR_COND_threads);
  }

  my_thread_global_init_done= FALSE;
}


/**
  Allocate thread specific memory for the thread, used by mysys and dbug

  @note This function may called multiple times for a thread, for example
  if one uses my_init() followed by mysql_server_init().

  @retval FALSE  ok
  @retval TRUE   Fatal error; mysys/dbug functions can't be used
*/

my_bool my_thread_init()
{
  struct st_my_thread_var *tmp;

  if (!my_thread_global_init_done)
    return TRUE; /* cannot proceed with unintialized library */

  if (mysys_thread_var())
    return FALSE;

#ifdef _WIN32
  install_sigabrt_handler();
#endif

  if (!(tmp= (struct st_my_thread_var *) calloc(1, sizeof(*tmp))))
    return TRUE;

  mysql_cond_init(key_my_thread_var_suspend, &tmp->suspend);

  mysql_mutex_lock(&THR_LOCK_threads);
  tmp->id= ++thread_id;
  ++THR_thread_count;
  mysql_mutex_unlock(&THR_LOCK_threads);
  set_mysys_thread_var(tmp);

  return FALSE;
}


/**
  Deallocate memory used by the thread for book-keeping

  @note This may be called multiple times for a thread.
  This happens for example when one calls 'mysql_server_init()'
  mysql_server_end() and then ends with a mysql_end().
*/

void my_thread_end()
{
  struct st_my_thread_var *tmp= mysys_thread_var();

#ifdef HAVE_PSI_INTERFACE
  /*
    Remove the instrumentation for this thread.
    This must be done before trashing st_my_thread_var,
    because the LF_HASH depends on it.
  */
  PSI_THREAD_CALL(delete_current_thread)();
#endif

  if (tmp)
  {
#if !defined(DBUG_OFF)
    /* tmp->dbug is allocated inside DBUG library */
    if (tmp->dbug)
    {
      DBUG_POP();
      free(tmp->dbug);
      tmp->dbug= NULL;
    }
#endif
    mysql_cond_destroy(&tmp->suspend);
    free(tmp);

    /*
      Decrement counter for number of running threads. We are using this
      in my_thread_global_end() to wait until all threads have called
      my_thread_end and thus freed all memory they have allocated in
      my_thread_init() and DBUG_xxxx
    */
    mysql_mutex_lock(&THR_LOCK_threads);
    DBUG_ASSERT(THR_thread_count != 0);
    if (--THR_thread_count == 0)
      mysql_cond_signal(&THR_COND_threads);
    mysql_mutex_unlock(&THR_LOCK_threads);
  }
  set_mysys_thread_var(NULL);
}


struct st_my_thread_var *mysys_thread_var()
{
  if (THR_KEY_mysys_initialized)
    return  (struct st_my_thread_var*)my_get_thread_local(THR_KEY_mysys);
  return NULL;
}


int set_mysys_thread_var(struct st_my_thread_var *mysys_var)
{
  if (THR_KEY_mysys_initialized)
    return my_set_thread_local(THR_KEY_mysys, mysys_var);
  return 0;
}


#ifndef DBUG_OFF
void **my_thread_var_dbug()
{
  struct st_my_thread_var *tmp;
  /*
    Instead of enforcing DBUG_ASSERT(THR_KEY_mysys_initialized) here,
    which causes any DBUG_ENTER and related traces to fail when
    used in init / cleanup code, we are more tolerant:
    using DBUG_ENTER / DBUG_PRINT / DBUG_RETURN
    when the dbug instrumentation is not in place will do nothing.
  */
  if (! THR_KEY_mysys_initialized)
    return NULL;
  tmp= mysys_thread_var();
  return tmp ? &tmp->dbug : NULL;
}
#endif /* DBUG_OFF */


#ifdef _WIN32
/*
  In Visual Studio 2005 and later, default SIGABRT handler will overwrite
  any unhandled exception filter set by the application  and will try to
  call JIT debugger. This is not what we want, this we calling __debugbreak
  to stop in debugger, if process is being debugged or to generate 
  EXCEPTION_BREAKPOINT and then handle_segfault will do its magic.
*/

static void my_sigabrt_handler(int sig)
{
  __debugbreak();
}

static void install_sigabrt_handler()
{
  /*abort() should not override our exception filter*/
  _set_abort_behavior(0,_CALL_REPORTFAULT);
  signal(SIGABRT,my_sigabrt_handler);
}
#endif

