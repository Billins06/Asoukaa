import {
  ExceptionFilter, Catch, ArgumentsHost,
  HttpException, HttpStatus, Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionsFilter');

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx    = host.switchToHttp();
    const res    = ctx.getResponse<Response>();
    const req    = ctx.getRequest<Request>();
    const status = exception instanceof HttpException
      ? exception.getStatus()
      : HttpStatus.INTERNAL_SERVER_ERROR;

    const exceptionResponse = exception instanceof HttpException
      ? exception.getResponse()
      : 'Erreur interne du serveur';

    // ⚠️ Nest renvoie souvent un OBJET pour exception.getResponse() (ex :
    // { statusCode, message: [...], error } pour toute erreur du
    // ValidationPipe). Avant, on empilait cet objet tel quel sous notre
    // propre clé "message" → le JSON final devenait
    // message: { statusCode, message: [...], error }, un objet au lieu
    // d'une chaîne ou d'un tableau. Résultat : côté Flutter, tout code qui
    // lit response.data['message'] comme String/List ne matchait jamais
    // et retombait sur un message générique, quelle que soit l'erreur
    // réelle (ex : "Type d'engin invalide" invisible, remplacé par
    // "Données invalides"). On aplatit donc le message ici.
    let message: unknown;
    let validationError: string | undefined;
    if (typeof exceptionResponse === 'string') {
      message = exceptionResponse;
    } else if (exceptionResponse && typeof exceptionResponse === 'object') {
      const body = exceptionResponse as Record<string, unknown>;
      message = body.message ?? exceptionResponse;
      validationError = typeof body.error === 'string' ? body.error : undefined;
    } else {
      message = exceptionResponse;
    }

    // ⚠️ Sans ce log, toute erreur non-HttpException (bug de code,
    // requete SQL invalide, etc.) etait totalement invisible : le
    // client ne voyait que "Erreur interne du serveur" et rien
    // n'apparaissait dans la console du serveur non plus.
    if (!(exception instanceof HttpException)) {
      this.logger.error(
        `${req.method} ${req.url} → 500 : ${(exception as Error)?.message ?? exception}`,
        (exception as Error)?.stack,
      );
    }

    res.status(status).json({
      statusCode: status,
      timestamp:  new Date().toISOString(),
      path:       req.url,
      message,
      ...(validationError ? { error: validationError } : {}),
    });
  }
}