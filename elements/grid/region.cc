/*
 * region.{cc,hh} -- Rectangular region class
 * Douglas S. J. De Couto
 *
 * Copyright (c) 2000 Massachusetts Institute of Technology.
 *
 * This software is being provided by the copyright holders under the GNU
 * General Public License, either version 2 or, at your discretion, any later
 * version. For more information, see the `COPYRIGHT' file in the source
 * distribution.
 */

#include <stdio.h>
#include "region.hh"

static double 
max(double a, double b) 
{ return a > b ? a : b; }

static double 
min(double a, double b) 
{ return a > b ? b : a; }

String
RectRegion::s() 
{
  char buf[50];
  if (empty())
    snprintf(buf, 50, "<empty rgn>");
  else
    snprintf(buf, 50, "(%f, %f) +%f +%f", _x, _y, _w, _h);
  return String(buf);
}

RectRegion
RectRegion::intersect(RectRegion &r)
{
  RectRegion ret; // empty default region
  if (!(r._x > _x + _w ||
	r._x + r._w < _x ||
	r._y > _y + _h ||
	r._y + r._h < _y)) {
    ret._x = max(_x, r._x);
    ret._y = max(_y, r._y);
    ret._w = min(_x + _w, r._x + r._w) - ret._x;
    ret._h = min(_y + _h, r._h + r._h) - ret._y;
  }
  return ret;  
}
